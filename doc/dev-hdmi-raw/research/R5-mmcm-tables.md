# R5: DRP tables of the HDMI MMCM (`video_out_clock.vhd`)

## 1. Result in brief

- `doc/dev-hdmi-raw/tools/mmcm_tables.py` computes every DRP word of a `video_out_clock.vhd` table from `CLKFBOUT_MULT_F`, `DIVCLK_DIVIDE`, `CLKOUT0_DIVIDE_F` and `CLKOUT1_DIVIDE` with a transcription of the XAPP888 reference functions (`mmcme2_drp_func.h` v1.31) and the ROM assembly of the XAPP888 reference design (`mmcme2_drp.v`).
- All eight existing tables are regenerated bit for bit (184 rows: table address, DRP address with end flag, data and mask). The frequency-relevant fields (counters, fractional fields, DIVCLK, filter) come out of the unmodified XAPP888 functions. Five uniform conventions of the spreadsheet that made the existing tables are reproduced on top (section 4.2); all five are frequency-neutral.
- An independent decoder (`decode` functions of `doc/dev-ntsc/tools/w2_checks.py`) reads M, D, O0 and O1 back from every existing table and from every generated table; all agree with the parameters.
- The three new tables (codes `1000`, `1001`, `1010`) pass every MMCM limit of DS181 (speed grade -2) and UG472. Each of them reuses words and code paths that the existing tables already exercise; what is new per table is listed in section 5.
- A GHDL simulation of a copy of `video_out_clock.vhd` with `clk_sel` widened to 4 bits (the change list of section 8) and the three new tables loads all 11 tables (12 loads) through the real state machine into a DRP register model; all 276 register values are as expected (section 7).
- Hazard found for the widening: a code without a table (`1011` to `1111`) hangs the loader for good (section 7.2).

## 2. How the tables are used

`cfg_tbl` is a synchronous ROM of 40-bit rows: bits 39..32 the DRP address (bit 39 set marks the last row), bits 31..16 the write data, bits 15..0 the read mask. The table of code `sel` starts at row `sel * 32` (`cfg_tbl_addr <= sel & "00000"` in state `RESET`), and the row counter is the low 5 bits of `cfg_tbl_addr`. Every table has 23 rows in ascending DRP address order: `0x06` to `0x16` (CLKOUT5, CLKOUT0 to CLKOUT4, CLKOUT6, CLKFBOUT, two registers each, then DIVCLK), `0x18` to `0x1A` (lock), `0x28` (power), `0x4E` and `0x4F` (filter, the last row written as `x"CF"`).

Each row is a read-modify-write: `DI = (DO and mask) or (data and not mask)`, so a mask bit 1 keeps the bit that the MMCM has, a mask bit 0 takes the table bit. The whole table is written while the MMCM is held in reset (`cfg_rst = '1'` from the end of `RESET_WAIT` until `LOCK_WAIT`), so the row order has no effect.

CLKOUT0 is the serializer clock (`clko_x5`, divider n), CLKOUT1 the pixel clock (divider 5n); CLKOUT2 to CLKOUT6 are unused and set to divide 10. The reference clock is 100 MHz (generic `fref`).

### 2.1 What happens when `clk_sel` changes

| Step | State | Effect |
|---|---|---|
| change seen | `IDLE` | `'0' & sel /= sel_prev` (or `locked_s = '0'`): `clk_mux <= '0'`, the `BUFGMUX_CTRL` switches `hdmi_clk` to the 50 MHz backup clock `clki_div` |
| 4 cycles | `RESET_WAIT` | lets the glitch-free clock switch settle, then `rsto_req <= '1'` and `cfg_rst <= '1'`: MMCM in reset, HDMI domain in reset (`rsto`) |
| 1 cycle | `RESET` | `sel_prev <= '0' & sel`, `cfg_tbl_addr <= sel & "00000"` |
| 23 rows | `TBL`, `RD`, `RD_WAIT`, `WR`, `WR_WAIT` | one DRP read and one DRP write per row |
| lock | `LOCK_WAIT` | `cfg_rst <= '0'`; when `locked_s = '1'`: `clk_mux <= '1'`, `rsto_req <= '0'` |

In the simulation (DRP answer after 3 DCLK cycles, lock 20 µs after reset release) one change takes 22.9 µs, of which about 2.9 µs is the table load. On the hardware the lock adds up to 100 µs (`MMCM_TLOCKMAX`, DS181 Table 37). During the whole sequence the HDMI side runs on the 50 MHz backup clock and is held in reset; the display sees a short loss of signal, as with every HDMI mode change today.

### 2.2 Power-on

The first table is always loaded; the MMCM never runs on its static attributes. `reset_m2m_n_o` of `reset_manager.vhd` has no initial value, so `rsti = not reset_m2m_n` is high in the first cycles after configuration. That holds the MMCM in reset (`mmcm_rst <= cfg_rst or rsti`), sets `sel_prev` to all ones and the state to `RESET`, so the table of the current code is written as soon as `rsti` falls. `clk_mux` starts at 0 (backup clock). The static attributes (`clkfbout_mult_f 37.125`, `divclk_divide 5`, `clkout0_divide_f 2.0`, `clkout1_divide 10`) matter only for static timing analysis: `M2M/common.xdc` derives `hdmi_clk` and `tmds_clk` from them (section 6.2).

## 3. Method

The reference is XAPP888 (v1.8, 2019) with its reference design:

- `mmcme2_drp_func.h` v1.31 (19 Sep 2018): `mmcm_divider`, `mmcm_phase`, `mmcm_count_calc`, `mmcm_frac_count_calc`, `mmcm_lock_lookup`, `mmcm_filter_lookup`. The Clocking Wizard ships the same functions as `mmcm_pll_drp_func_7s_mmcm.vh` (v1.04, 2014) under the names `mmcm_pll_divider`, `mmcm_pll_phase`, `mmcm_pll_lock_lookup`, `mmcm_pll_filter_lookup`, `mmcm_pll_count_calc`. Both versions have the same lock table and the same HIGH (= OPTIMIZED) filter table. They differ in the fractional register 2: v1.04 copies EDGE and `NO_COUNT` of the integer part into it, v1.31 writes them as 0. The existing tables follow v1.31 (for example `0x4800` for M 31.5, where v1.04 gives `0x4880`), so v1.31 is the reference.
- `mmcme2_drp.v` of the same reference design: how the function results become DRP words and masks (shared fractional bits of CLKOUT0 in CLKOUT5 register 2 and of CLKFBOUT in CLKOUT6 register 2, DIVCLK word, lock and filter bit placement).

The generator transcribes these functions for phase 0 and 50 % duty cycle, including the Verilog details that matter (the 1-based bit numbering of `round_frac`, the 8-bit arithmetic of `mmcm_frac_count_calc`, fractional mode only when the fraction is not 0). It has two output styles: `xapp888` (the reference ROM words) and `m2m` (the same plus the five conventions of the existing tables, section 4.2). Bandwidth is OPTIMIZED, as in the MMCM instance.

Commands:

```
python3 doc/dev-hdmi-raw/tools/mmcm_tables.py check [-v] [--vhdl FILE]
python3 doc/dev-hdmi-raw/tools/mmcm_tables.py new [--alternatives]
python3 doc/dev-hdmi-raw/tools/mmcm_tables.py gen M D O0 O1 --base 0x100 --addr-style hex9
python3 doc/dev-hdmi-raw/tools/mmcm_tables.py limits M D O0 O1
python3 doc/dev-hdmi-raw/tools/mmcm_tables.py equiv M D O0 O1
```

`check` parses the tables of the file (2- and 3-digit labels, `x"NN"`, `9x"NNN"` and `16#NNN#`), regenerates each from its comment header, compares every row bit by bit, lists every word that differs from the pure reference with its reason, decodes every table with `w2_checks.py` and checks which lock and filter lookup entries the words come from. It exits with 0 only if everything matches and no difference is unexplained.

## 4. Validation against the existing tables

### 4.1 Result

| `clk_sel` | M | D | O0 | O1 | Pixel clock | Rows | Bit-exact (style `m2m`) | `w2_checks.py` decode | Lock / filter entry |
|---|---|---|---|---|---|---|---|---|---|
| `000` | 31.500 | 5 | 5 | 25 | 25.200000 MHz | 23 | yes | M 31.5 D 5 O0 5 O1 25 | M 31 / M 31 |
| `001` | 47.250 | 5 | 7 | 35 | 27.000000 MHz | 23 | yes | M 47.25 D 5 O0 7 O1 35 | M 47 / M 47 |
| `010` | 37.125 | 5 | 2 | 10 | 74.250000 MHz | 23 | yes | M 37.125 D 5 O0 2 O1 10 | M 37 / M 37 |
| `011` | 37.125 | 5 | 1 | 5 | 148.500000 MHz | 23 | yes | M 37.125 D 5 O0 1 O1 5 | M 37 / M 37 |
| `100` | 17.625 | 2 | 7 | 35 | 25.178571 MHz | 23 | yes | M 17.625 D 2 O0 7 O1 35 | M 17 / M 17 |
| `101` | 21.625 | 2 | 8 | 40 | 27.031250 MHz | 23 | yes | M 21.625 D 2 O0 8 O1 40 | M 21 / M 21 |
| `110` | 22.250 | 3 | 2 | 10 | 74.166667 MHz | 23 | yes | M 22.25 D 3 O0 2 O1 10 | M 22 / M 22 |
| `111` | 10 | 1 | 5 | 25 | 40.000000 MHz | 23 | yes | M 10 D 1 O0 5 O1 25 | M 10 / M 10 |

The eight tables cover six fractional CLKFBOUT values (fractions 1/8, 2/8, 4/8, 5/8 with odd and even integer parts), one integer CLKFBOUT, D 1, 2, 3, 5, odd and even output dividers and divide 1. C64MEGA65 selects `001` (576p50 and 480p59.94), `010` (720p50) and `110` (720p59.94); `000`, `011`, `100`, `101` and `111` are not selectable in its menu.

The comment header of the 27.000 MHz table says "Actual frequency = 74.250 MHz"; its rows produce 27.000 MHz.

### 4.2 Differences to the pure XAPP888 reference ROM

All 131 words in which the file differs from the reference ROM fall into five classes, each uniform over all tables:

| Class | Words | What the file has | Reference | Effect |
|---|---|---|---|---|
| Reserved bit 12 of ClkReg1 (`0x06` ... `0x14`) | 64 | 1 | 0 | none: the mask `0x1000` keeps the MMCM's own bit |
| Mask of ClkReg2 of CLKOUT1 to CLKOUT6 (`0x07`, `0x0B`, `0x0D`, `0x0F`, `0x11`, `0x13`) | 48 | `0x8000` | `0xFC00` / `0xC000` | reserved bits 14..10 (CLKOUT1 to 4) or 14 (CLKOUT5, 6) written as 0 instead of retained (XAPP888 Tables 3 to 6: "retain the previous value"); data bits are identical |
| EDGE of DIVCLK for odd D (`0x16`) | 5 | 0 | 1 | duty cycle of the divided reference only; the PFD compares rising edges ("the duty cycle is ancillary", UG472 chapter 3) |
| Lock fields (`0x18` and `0x1A`) | 13 | bits 9..8 of `LockCnt` and `LockSatHigh` as `{0, bit 9}` | the lookup value | see 4.3 |
| EDGE of CLKOUT0 with divide 1 (`0x09` of table `011`) | 1 | `0x00C0` | `0x0040` | none: `NO_COUNT` bypasses the high and low counters |

### 4.3 The lock fields

The lock words of the existing tables are not the XAPP888 values. `LockSatHigh` is `0x1E9` everywhere instead of `0x3E9`, and `LockCnt` is:

| M (integer part) | XAPP888 `LockCnt` | In the file |
|---|---|---|
| 10 | `0x3E8` (1000) | `0x1E8` (488) |
| 17 | `0x23F` (575) | `0x13F` (319) |
| 21 | `0x1DB` (475) | `0x0DB` (219) |
| 22 | `0x1C2` (450) | `0x0C2` (194) |
| 31 | `0x12C` (300) | `0x02C` (44) |
| 37, 47 | `0x0FA` (250) | `0x0FA` (250) |

These values cover all four combinations of bits 9..8, and exactly one simple rule fits all of them: bit 9 moves to bit 8, bit 8 is lost, bit 9 becomes 0. The file values are not monotonic in M (44 at M 31, 250 at M 37), while the characterized table falls steadily from 1000 to 250, so the file values are a bit-placement error of the spreadsheet (`video_out_clock.xls` of the tyto2 project) and not a different characterization table. The mechanism inside the spreadsheet is unknown. Upstream tyto2 has the same words in tables `000` to `011`.

The fields only tune the lock detector: a smaller `LockCnt` lets LOCKED rise after fewer reference cycles in the lock window. Every existing table carries the error, including the field-proven `001` and `010` (`LockSatHigh`) and `110` (`LockCnt` too), and all of them lock. The generator reproduces the rule in style `m2m`; style `xapp888` gives the reference values.

## 5. The new tables (`clk_sel` `1000`, `1001`, `1010`)

Style `m2m` (the conventions of the eight existing tables), labels as VHDL-2008 bit-string literals for a 9-bit `cfg_tbl_addr` (the file is compiled as VHDL-2008 in all four `.xpr` projects and by `doc/dev-ntsc/tools/analyze.py`). Paste before `when others`.

| Code | Mode | M | D | O0 | O1 | VCO | PFD | Pixel clock | Frame rate (C64: PAL 50.124291 Hz, NTSC 59.826105 Hz) |
|---|---|---|---|---|---|---|---|---|---|
| `1000` | PAL 720p, 1980 x 750 | 33.500 | 3 | 3 | 15 | 1116.667 MHz | 33.333 MHz | 74.444444 MHz | 50.130939 Hz (+132.6 ppm) |
| `1001` | PAL 576p, 864 x 624 | 28.375 | 3 | 7 | 35 | 945.833 MHz | 33.333 MHz | 27.023810 MHz | 50.124291 Hz (exact) |
| `1010` | NTSC 720p, 1650 x 750 | 29.625 | 4 | 2 | 10 | 740.625 MHz | 25.000 MHz | 74.062500 MHz | 59.848485 Hz (+374.1 ppm) |

### 5.1 `1000`: PAL 720p, 74.444444 MHz

```
          -- PAL 720p (1280x720, 1980 x 750 total) at the C64 frame rate: 50.130939 Hz
          -- Desired frequency = 74.444 MHz
          -- CLKFBOUT_MULT_F   = 33.500
          -- DIVCLK_DIVIDE     = 3
          -- CLKOUT0_DIVIDE_F  = 3.000
          -- CLKOUT1_DIVIDE    = 15
          -- Actual frequency  = 74.444 MHz
          when 9x"100" => data := x"06" & x"1145" & x"1000";  -- CLKOUT5 Register 1
          when 9x"101" => data := x"07" & x"0000" & x"8000";  -- CLKOUT5 Register 2
          when 9x"102" => data := x"08" & x"1042" & x"1000";  -- CLKOUT0 Register 1
          when 9x"103" => data := x"09" & x"0080" & x"8000";  -- CLKOUT0 Register 2
          when 9x"104" => data := x"0A" & x"11C8" & x"1000";  -- CLKOUT1 Register 1
          when 9x"105" => data := x"0B" & x"0080" & x"8000";  -- CLKOUT1 Register 2
          when 9x"106" => data := x"0C" & x"1145" & x"1000";  -- CLKOUT2 Register 1
          when 9x"107" => data := x"0D" & x"0000" & x"8000";  -- CLKOUT2 Register 2
          when 9x"108" => data := x"0E" & x"1145" & x"1000";  -- CLKOUT3 Register 1
          when 9x"109" => data := x"0F" & x"0000" & x"8000";  -- CLKOUT3 Register 2
          when 9x"10A" => data := x"10" & x"1145" & x"1000";  -- CLKOUT4 Register 1
          when 9x"10B" => data := x"11" & x"0000" & x"8000";  -- CLKOUT4 Register 2
          when 9x"10C" => data := x"12" & x"1145" & x"1000";  -- CLKOUT6 Register 1
          when 9x"10D" => data := x"13" & x"3000" & x"8000";  -- CLKOUT6 Register 2
          when 9x"10E" => data := x"14" & x"1410" & x"1000";  -- CLKFBOUT Register 1
          when 9x"10F" => data := x"15" & x"4800" & x"8000";  -- CLKFBOUT Register 2
          when 9x"110" => data := x"16" & x"0042" & x"C000";  -- DIVCLK Register
          when 9x"111" => data := x"18" & x"002C" & x"FC00";  -- Lock Register 1
          when 9x"112" => data := x"19" & x"7C01" & x"8000";  -- Lock Register 2
          when 9x"113" => data := x"1A" & x"7DE9" & x"8000";  -- Lock Register 3
          when 9x"114" => data := x"28" & x"FFFF" & x"0000";  -- Power Register
          when 9x"115" => data := x"4E" & x"0900" & x"66FF";  -- Filter Register 1
          when 9x"116" => data := x"CF" & x"1000" & x"666F";  -- Filter Register 2
```

Compared with table `000` (M 31.5, D 5, O0 5, O1 25) only four words differ: CLKOUT0 register 1, CLKOUT1 register 1, CLKFBOUT register 1 and DIVCLK. The fractional register 2 (`0x4800`), the shared fractional bits (`0x3000`), the lock words and the filter words are identical to table `000` (same fraction 4/8 with odd integer part; integer parts 31 and 33 share the lock and filter entries). New code paths: an output divider of 3 (odd, EDGE set, the same path as 5, 7, 25 and 35) and DIVCLK 3 (the same word `0x0042` as table `110`).

### 5.2 `1001`: PAL 576p, 27.023810 MHz

```
          -- PAL 576p (720x576, 864 x 624 total) at the C64 frame rate: 50.124291 Hz
          -- Desired frequency = 27.024 MHz
          -- CLKFBOUT_MULT_F   = 28.375
          -- DIVCLK_DIVIDE     = 3
          -- CLKOUT0_DIVIDE_F  = 7.000
          -- CLKOUT1_DIVIDE    = 35
          -- Actual frequency  = 27.024 MHz
          when 9x"120" => data := x"06" & x"1145" & x"1000";  -- CLKOUT5 Register 1
          when 9x"121" => data := x"07" & x"0000" & x"8000";  -- CLKOUT5 Register 2
          when 9x"122" => data := x"08" & x"10C4" & x"1000";  -- CLKOUT0 Register 1
          when 9x"123" => data := x"09" & x"0080" & x"8000";  -- CLKOUT0 Register 2
          when 9x"124" => data := x"0A" & x"1452" & x"1000";  -- CLKOUT1 Register 1
          when 9x"125" => data := x"0B" & x"0080" & x"8000";  -- CLKOUT1 Register 2
          when 9x"126" => data := x"0C" & x"1145" & x"1000";  -- CLKOUT2 Register 1
          when 9x"127" => data := x"0D" & x"0000" & x"8000";  -- CLKOUT2 Register 2
          when 9x"128" => data := x"0E" & x"1145" & x"1000";  -- CLKOUT3 Register 1
          when 9x"129" => data := x"0F" & x"0000" & x"8000";  -- CLKOUT3 Register 2
          when 9x"12A" => data := x"10" & x"1145" & x"1000";  -- CLKOUT4 Register 1
          when 9x"12B" => data := x"11" & x"0000" & x"8000";  -- CLKOUT4 Register 2
          when 9x"12C" => data := x"12" & x"1145" & x"1000";  -- CLKOUT6 Register 1
          when 9x"12D" => data := x"13" & x"0C00" & x"8000";  -- CLKOUT6 Register 2
          when 9x"12E" => data := x"14" & x"134D" & x"1000";  -- CLKFBOUT Register 1
          when 9x"12F" => data := x"15" & x"3C00" & x"8000";  -- CLKFBOUT Register 2
          when 9x"130" => data := x"16" & x"0042" & x"C000";  -- DIVCLK Register
          when 9x"131" => data := x"18" & x"005E" & x"FC00";  -- Lock Register 1
          when 9x"132" => data := x"19" & x"7C01" & x"8000";  -- Lock Register 2
          when 9x"133" => data := x"1A" & x"7DE9" & x"8000";  -- Lock Register 3
          when 9x"134" => data := x"28" & x"FFFF" & x"0000";  -- Power Register
          when 9x"135" => data := x"4E" & x"0900" & x"66FF";  -- Filter Register 1
          when 9x"136" => data := x"CF" & x"1000" & x"666F";  -- Filter Register 2
```

CLKOUT0 and CLKOUT1 (`0x10C4`, `0x1452`, EDGE `0x0080`) are the words of the field-proven table `001`; DIVCLK (`0x0042`) and the fractional branch (even integer part with a small fraction: high and low time both one less, `FRAC_WF_R` and `FRAC_WF_F` set, shared word `0x0C00`) are those of table `110`; the filter words (`0x0900`, `0x1000`) are those of tables `000`, `010` and `011`. New are the values in that branch (CLKFBOUT `0x134D`: high and low time 13; `0x3C00`: FRAC 3) and the lock word `0x005E` (XAPP888 `0x015E` for M 28, same spreadsheet rule).

The equivalent M 56.750, D 6, O0 7, O1 35 gives the same VCO and pixel clock but has half the PFD (16.7 MHz, below the lowest PFD of any existing table, 20 MHz) and filter words that no existing table uses (`0x1100`, `0x1800`, entry M 56). M 28.375 with D 3 is the better choice.

### 5.3 `1010`: NTSC 720p, 74.062500 MHz

```
          -- NTSC 720p (1280x720, 1650 x 750 total) at the C64 frame rate: 59.848485 Hz
          -- Desired frequency = 74.062 MHz
          -- CLKFBOUT_MULT_F   = 29.625
          -- DIVCLK_DIVIDE     = 4
          -- CLKOUT0_DIVIDE_F  = 2.000
          -- CLKOUT1_DIVIDE    = 10
          -- Actual frequency  = 74.062 MHz
          when 9x"140" => data := x"06" & x"1145" & x"1000";  -- CLKOUT5 Register 1
          when 9x"141" => data := x"07" & x"0000" & x"8000";  -- CLKOUT5 Register 2
          when 9x"142" => data := x"08" & x"1041" & x"1000";  -- CLKOUT0 Register 1
          when 9x"143" => data := x"09" & x"0000" & x"8000";  -- CLKOUT0 Register 2
          when 9x"144" => data := x"0A" & x"1145" & x"1000";  -- CLKOUT1 Register 1
          when 9x"145" => data := x"0B" & x"0000" & x"8000";  -- CLKOUT1 Register 2
          when 9x"146" => data := x"0C" & x"1145" & x"1000";  -- CLKOUT2 Register 1
          when 9x"147" => data := x"0D" & x"0000" & x"8000";  -- CLKOUT2 Register 2
          when 9x"148" => data := x"0E" & x"1145" & x"1000";  -- CLKOUT3 Register 1
          when 9x"149" => data := x"0F" & x"0000" & x"8000";  -- CLKOUT3 Register 2
          when 9x"14A" => data := x"10" & x"1145" & x"1000";  -- CLKOUT4 Register 1
          when 9x"14B" => data := x"11" & x"0000" & x"8000";  -- CLKOUT4 Register 2
          when 9x"14C" => data := x"12" & x"1145" & x"1000";  -- CLKOUT6 Register 1
          when 9x"14D" => data := x"13" & x"3000" & x"8000";  -- CLKOUT6 Register 2
          when 9x"14E" => data := x"14" & x"138E" & x"1000";  -- CLKFBOUT Register 1
          when 9x"14F" => data := x"15" & x"5800" & x"8000";  -- CLKFBOUT Register 2
          when 9x"150" => data := x"16" & x"0082" & x"C000";  -- DIVCLK Register
          when 9x"151" => data := x"18" & x"0045" & x"FC00";  -- Lock Register 1
          when 9x"152" => data := x"19" & x"7C01" & x"8000";  -- Lock Register 2
          when 9x"153" => data := x"1A" & x"7DE9" & x"8000";  -- Lock Register 3
          when 9x"154" => data := x"28" & x"FFFF" & x"0000";  -- Power Register
          when 9x"155" => data := x"4E" & x"0900" & x"66FF";  -- Filter Register 1
          when 9x"156" => data := x"CF" & x"1000" & x"666F";  -- Filter Register 2
```

Compared with table `010` (M 37.125, D 5, O0 2, O1 10) five words differ: CLKOUT6 register 2, CLKFBOUT registers 1 and 2, DIVCLK and lock register 1. The output dividers are those of `010` and `110`; the fractional branch (fraction 5/8, odd integer part) is that of tables `100` and `101`; the filter words are those of `000`, `010` and `011`. New: DIVCLK 4 (even, `0x0082`, same path as D 2) and the lock word `0x0045` (XAPP888 `0x0145` for M 29).

### 5.4 Reference-style words

If the lock words should follow XAPP888 instead of the existing tables, only these words change (style `xapp888`, all other data words identical; it also writes masks `0xFC00` / `0xC000` for the register-2 rows of CLKOUT1 to CLKOUT6 and 0 into bit 12 of ClkReg1):

| Code | DIVCLK `0x16` | Lock 1 `0x18` | Lock 3 `0x1A` |
|---|---|---|---|
| `1000` | `0x2042` | `0x012C` | `0x7FE9` |
| `1001` | `0x2042` | `0x015E` | `0x7FE9` |
| `1010` | `0x0082` (unchanged) | `0x0145` | `0x7FE9` |

Recommendation: keep style `m2m`, so the new tables belong to the same family as the eight tables that run today; the lock-word error has been present in every load of every existing table without a known effect.

## 6. Limit checks (xc7a200t, speed grade -2)

### 6.1 MMCM limits

Sources: DS181 v1.27.1 Table 37 (MMCM), Table 32 (BUFG), Table 15 (OSERDES); UG472 v1.14 Table 3-7 (attributes) and chapter 3.

| Check | Limit | `1000` | `1001` | `1010` |
|---|---|---|---|---|
| `CLKFBOUT_MULT_F` | 2.000 to 64.000 in steps of 0.125 | 33.500 | 28.375 | 29.625 |
| `DIVCLK_DIVIDE` | 1 to 106 | 3 | 3 | 4 |
| `CLKOUT0_DIVIDE_F` | 1, or 2.000 to 128.000 | 3 | 7 | 2 |
| `CLKOUT1_DIVIDE` | 1 to 128 | 15 | 35 | 10 |
| CLKIN | 10 to 800 MHz | 100 | 100 | 100 |
| PFD | 10 to 500 MHz | 33.333 | 33.333 | 25.000 |
| VCO | 600 to 1440 MHz (-2); 1200 on -1 | 1116.667 | 945.833 | 740.625 |
| Outputs | 4.69 to 800 MHz | 372.222 / 74.444 | 135.119 / 27.024 | 370.313 / 74.063 |
| Serializer clock on BUFG | 628 MHz (`FMAX_BUFG`) | 372.222 | 135.119 | 370.313 |
| TMDS bit rate (DDR OSERDES transmitter, DS181 Table 15) | 1250 Mb/s | 744.4 | 270.2 | 740.6 |
| Lock and filter index int(M) | 1 to 64 | 33 | 28 | 29 |

All pass; every VCO is also below the 1200 MHz of a -1 part, and every PFD is above the 20 MHz of the existing D 5 tables.

### 6.2 Other conditions

- Fractional `CLKFBOUT_MULT_F`: only CLKOUT0 and CLKFBOUT can be fractional, the duty cycle is fixed at 50 % and fine phase shift is not allowed (UG472 chapter 3); none of that is used. The fractional settings of CLKFBOUT live in register 2 of CLKOUT6 (XAPP888 Table 6), which is unused. The existing tables use fractional feedback with the same `ZHOLD` / BUFG feedback.
- Odd CLKOUT0 dividers with 50 % duty cycle (3 in `1000`, 7 in `1001`): EDGE adds half a VCO cycle to the high time (XAPP888), as for 5 and 7 in the existing tables. Duty-cycle precision 0.2 ns (`MMCM_TOUTDUTY`).
- CLKOUT1 = 5 x CLKOUT0: both counters run from the same VCO with phase 0 and start together when the MMCM leaves reset, so every rising edge of CLKOUT1 coincides with every fifth rising edge of CLKOUT0 (15 = 5 x 3, 35 = 5 x 7, 10 = 5 x 2), as the OSERDES needs for CLK and CLKDIV. Same structure as all existing tables.
- Static timing: `M2M/common.xdc` times `hdmi_clk` and `tmds_clk` from the static attributes (74.25 / 371.25 MHz). Code `1000` runs at 74.444 / 372.222 MHz, 0.26 % faster than analysed. The comment above the MMCM instance asks for the fastest clock as the static configuration; setting the attributes to the `1000` values (`clkfbout_mult_f 33.5`, `divclk_divide 3`, `clkout0_divide_f 3.0`, `clkout1_divide 15`) makes the analysis cover all used modes. This changes only timing analysis, not behavior (section 2.2). Table `011` (148.5 MHz) has always been above the analysed frequency but is not selectable.
- Jitter values are only available from the Clocking Wizard (DS181 Table 37, note 3).

## 7. Simulation of the widened loader

### 7.1 Loading all tables

A scratch copy of `video_out_clock.vhd` with exactly the changes of section 8.1 (items 1 to 6) and the three new tables was simulated with GHDL 5.1.1 (`--std=08`) against behavioral models of `MMCME2_ADV` (a DRP register file with a known start pattern in every register, DRDY 3 DCLK cycles after DEN, LOCKED 20 µs after reset release, an assertion against DRP access outside reset), BUFG and `BUFGMUX_CTRL`, plus the real `cdc_stable.vhd`. The testbench selects `0010` at power-on, then `0000`, `0001`, `0011` ... `0111`, `1000`, `1001`, `1010` and `0010` again. After each load the model dumps the 23 registers, and a checker compares them with `(start and mask) or (data and not mask)` computed from the generator: 12 loads x 23 registers, all correct; each load takes 22.9 µs including the model's 20 µs lock.

The backup clock `clki_div` has no initial value, so it stays `'U'` in a simulation and `rsto` never updates while the backup clock is selected; the copy gives it `:= '0'`. On the hardware the flip-flop starts at 0; an initial value in the source would only help simulations.

### 7.2 A code without a table hangs the loader

For a code without a table, `cfg_tbl` returns `when others => (others => '0')`: DRP address `0x00`, data 0, mask 0, and no end flag. The loader then cycles through rows 0 to 31 of the empty table for ever, writing 0 into DRP address `0x00` with the MMCM in reset. It does not look at `sel` in these states, so a later change back to a valid code does not help; the simulation confirms: after `1011` neither `1011` nor the following `0010` ever locks. Only `rsti` (the M2M reset, a 1.5 s press of the reset button) recovers. With 3 bits every code had a table; with 4 bits the codes `1011` to `1111` have none.

The loader reads `sel` directly, not the synchronized `sel_s` (which `SYNC1` produces but nothing uses). A code is taken in state `RESET`, five cycles after the first changed bit was seen; a multi-bit change that is sampled half-way could produce an unused code. Two changes close this:

- `when others => data := x"A8" & x"FFFF" & x"0000";` (power register, end flag): a code without a table writes one harmless word and relocks with the previous settings. Rows 23 to 31 of valid tables are never reached, so nothing else changes.
- Use `sel_s` instead of `sel` in `IDLE` and `RESET` (lines 390, 406, 407); `cdc_stable` passes a value only after two equal samples.

## 8. Widening `clk_sel` to 4 bits: lines to change

Line numbers refer to the current files on branch `mh_implement_184`.

### 8.1 `M2M/vhdl/controllers/HDMI/video_out_clock.vhd`

1. Line 51: `sel : in std_logic_vector(2 downto 0)` to `(3 downto 0)`; lines 52 to 61, the comment listing the codes (`111` is the 40 MHz SVGA table, not "undefined"; add `1000` to `1010`).
2. Line 71: `sel_s` to `(3 downto 0)`.
3. Line 79: `sel_prev` to `(4 downto 0)` (it holds `'0' & sel`).
4. Line 88: `cfg_tbl_addr` to `(8 downto 0)`, comment "16 x 32 entries".
5. Lines 138 to 370: the 184 labels `when x"NN"` to `when 9x"0NN"` (a 9-bit case expression needs 9-bit choices; mechanical: `s/when x"\(..\)" =>/when 9x"0\1" =>/`). Insert the three blocks of section 5 before line 372 (`when others`).
6. Lines 464 and 469 to 475 (`SYNC1`): `G_DATA_SIZE => 5`, add `src_data_i(4) => sel(3)` and `dst_data_o(4) => sel_s(3)`.
7. Recommended: line 372 `when others` as in section 7.2; lines 390, 406, 407 with `sel_s`.
8. Recommended: lines 495, 500, 504, 530 (static attributes) as in section 6.2, with their comments.

Unchanged and correct with the wider types: line 390 (`'0' & sel /= sel_prev`), 406, 407 (`sel & "00000"` is 9 bits), 427, 430 (row counter `4 downto 0`), 445 (`sel_prev <= (others => '1')` still differs from every `'0' & sel`).

### 8.2 Other files

| File | Lines | Change |
|---|---|---|
| `M2M/vhdl/av_pipeline/video_modes_pkg.vhd` | 8 | `CLK_SEL : std_logic_vector(3 downto 0)` |
| same | 43, 63, 83, 107, 133, 157, 177, 198 | `"001"` to `"0001"` etc. (8 records); comment line 125; new records with `"1000"`, `"1001"`, `"1010"` |
| `M2M/vhdl/framework.vhd` | 370 | `qnice_clk_sel : std_logic_vector(3 downto 0)`; line 525 unchanged; the mode decode (lines 512 to 521) gets the new modes |
| `CORE/vhdl/test/tb_ntsc/tb_video_modes.vhd` | 99 (comment 12) | `r.CLK_SEL = "110"` to `"0110"` (a 3-bit literal against a 4-bit field compares false) |
| `doc/dev-ntsc/tools/w2_checks.py` | 101 | the label regex `when\s+x"(..)"` finds no `9x"0NN"` label (then `KeyError`); accept an optional width prefix and 3 digits |
| same | 373, 390, 396 (doc lines 10, 13) | `"110"`, `"010"`, `"001"` to 4-bit strings (`int(sel, 2) * 0x20` on line 99 works unchanged) |

`M2M/common.xdc` (generated clocks on the MMCM pins and `set_case_analysis` on `clk_mux_reg`) needs no change for the widening. `mmcm_tables.py check` reads the widened file unchanged (tested on the scratch copy: 11 tables, PASS).

## 9. Alternatives (not used)

| Setting | Pixel clock | Notes |
|---|---|---|
| PAL 576p M 56.750, D 6, O0 7, O1 35 | 27.023810 MHz | equivalent of `1001`; PFD 16.7 MHz, filter entry M 56 used by no existing table |
| PAL 576p M 47.375, D 7, O0 5, O1 25 | 27.071429 MHz (864 x 625: +159.3 ppm) | PFD 14.3 MHz |
| PAL 576p M 47.375, D 5, O0 7, O1 35 | 27.071429 MHz | equivalent of the previous one with PFD 20 MHz; differs from table `001` only in the FRAC field (`0x3800` instead of `0x2800`) |
| NTSC 480p M 43.125, D 4, O0 8, O1 40 | 26.953125 MHz (858 x 525: +165.3 ppm) | only legal setting for this clock; filter entry M 43 (`0x0800`, `0x8000`) used by no existing table |

All four pass the limits of section 6.1; `mmcm_tables.py new --alternatives` prints their tables. The two settings that had been planned for 576p and 480p:

```
          -- PAL 576p (720x576, 864 x 625 total) at the C64 frame rate: 50.132275 Hz
          -- Desired frequency = 27.071 MHz
          -- CLKFBOUT_MULT_F   = 47.375
          -- DIVCLK_DIVIDE     = 7
          -- CLKOUT0_DIVIDE_F  = 5.000
          -- CLKOUT1_DIVIDE    = 25
          -- Actual frequency  = 27.071 MHz
          when 9x"120" => data := x"06" & x"1145" & x"1000";  -- CLKOUT5 Register 1
          when 9x"121" => data := x"07" & x"0000" & x"8000";  -- CLKOUT5 Register 2
          when 9x"122" => data := x"08" & x"1083" & x"1000";  -- CLKOUT0 Register 1
          when 9x"123" => data := x"09" & x"0080" & x"8000";  -- CLKOUT0 Register 2
          when 9x"124" => data := x"0A" & x"130D" & x"1000";  -- CLKOUT1 Register 1
          when 9x"125" => data := x"0B" & x"0080" & x"8000";  -- CLKOUT1 Register 2
          when 9x"126" => data := x"0C" & x"1145" & x"1000";  -- CLKOUT2 Register 1
          when 9x"127" => data := x"0D" & x"0000" & x"8000";  -- CLKOUT2 Register 2
          when 9x"128" => data := x"0E" & x"1145" & x"1000";  -- CLKOUT3 Register 1
          when 9x"129" => data := x"0F" & x"0000" & x"8000";  -- CLKOUT3 Register 2
          when 9x"12A" => data := x"10" & x"1145" & x"1000";  -- CLKOUT4 Register 1
          when 9x"12B" => data := x"11" & x"0000" & x"8000";  -- CLKOUT4 Register 2
          when 9x"12C" => data := x"12" & x"1145" & x"1000";  -- CLKOUT6 Register 1
          when 9x"12D" => data := x"13" & x"2800" & x"8000";  -- CLKOUT6 Register 2
          when 9x"12E" => data := x"14" & x"15D7" & x"1000";  -- CLKFBOUT Register 1
          when 9x"12F" => data := x"15" & x"3800" & x"8000";  -- CLKFBOUT Register 2
          when 9x"130" => data := x"16" & x"00C4" & x"C000";  -- DIVCLK Register
          when 9x"131" => data := x"18" & x"00FA" & x"FC00";  -- Lock Register 1
          when 9x"132" => data := x"19" & x"7C01" & x"8000";  -- Lock Register 2
          when 9x"133" => data := x"1A" & x"7DE9" & x"8000";  -- Lock Register 3
          when 9x"134" => data := x"28" & x"FFFF" & x"0000";  -- Power Register
          when 9x"135" => data := x"4E" & x"1900" & x"66FF";  -- Filter Register 1
          when 9x"136" => data := x"CF" & x"0100" & x"666F";  -- Filter Register 2
```

```
          -- NTSC 480p (720x480, 858 x 525 total) at the C64 frame rate: 59.835997 Hz
          -- Desired frequency = 26.953 MHz
          -- CLKFBOUT_MULT_F   = 43.125
          -- DIVCLK_DIVIDE     = 4
          -- CLKOUT0_DIVIDE_F  = 8.000
          -- CLKOUT1_DIVIDE    = 40
          -- Actual frequency  = 26.953 MHz
          when 9x"160" => data := x"06" & x"1145" & x"1000";  -- CLKOUT5 Register 1
          when 9x"161" => data := x"07" & x"0000" & x"8000";  -- CLKOUT5 Register 2
          when 9x"162" => data := x"08" & x"1104" & x"1000";  -- CLKOUT0 Register 1
          when 9x"163" => data := x"09" & x"0000" & x"8000";  -- CLKOUT0 Register 2
          when 9x"164" => data := x"0A" & x"1514" & x"1000";  -- CLKOUT1 Register 1
          when 9x"165" => data := x"0B" & x"0000" & x"8000";  -- CLKOUT1 Register 2
          when 9x"166" => data := x"0C" & x"1145" & x"1000";  -- CLKOUT2 Register 1
          when 9x"167" => data := x"0D" & x"0000" & x"8000";  -- CLKOUT2 Register 2
          when 9x"168" => data := x"0E" & x"1145" & x"1000";  -- CLKOUT3 Register 1
          when 9x"169" => data := x"0F" & x"0000" & x"8000";  -- CLKOUT3 Register 2
          when 9x"16A" => data := x"10" & x"1145" & x"1000";  -- CLKOUT4 Register 1
          when 9x"16B" => data := x"11" & x"0000" & x"8000";  -- CLKOUT4 Register 2
          when 9x"16C" => data := x"12" & x"1145" & x"1000";  -- CLKOUT6 Register 1
          when 9x"16D" => data := x"13" & x"2400" & x"8000";  -- CLKOUT6 Register 2
          when 9x"16E" => data := x"14" & x"1554" & x"1000";  -- CLKFBOUT Register 1
          when 9x"16F" => data := x"15" & x"1800" & x"8000";  -- CLKFBOUT Register 2
          when 9x"170" => data := x"16" & x"0082" & x"C000";  -- DIVCLK Register
          when 9x"171" => data := x"18" & x"00FA" & x"FC00";  -- Lock Register 1
          when 9x"172" => data := x"19" & x"7C01" & x"8000";  -- Lock Register 2
          when 9x"173" => data := x"1A" & x"7DE9" & x"8000";  -- Lock Register 3
          when 9x"174" => data := x"28" & x"FFFF" & x"0000";  -- Power Register
          when 9x"175" => data := x"4E" & x"0800" & x"66FF";  -- Filter Register 1
          when 9x"176" => data := x"CF" & x"8000" & x"666F";  -- Filter Register 2
```

## 10. Sources

- XAPP888 v1.8 "MMCM and PLL Dynamic Reconfiguration" (docs.amd.com), Tables 1 to 15.
- `mmcme2_drp_func.h` v1.31 and `mmcme2_drp.v` of the XAPP888 reference design, copy at https://github.com/mdovey/zxnexys/tree/af28c09b3fca3b69f17af3b99f913c09c0cce3a6/srcs/sources/imports/Xilinx (an identical copy of the header: https://github.com/oung666/gnss_fpga/blob/1d3cf7fc551e14c550ac22182665d9e4292ef9ba/gnss.srcs/sources_1/new/mmcme2_drp_func.h).
- Clocking Wizard `mmcm_pll_drp_func_7s_mmcm.vh` v1.04 and `pix_clk_mmcm_pll_drp.v`: https://github.com/PacktPublishing/Learn-FPGA-Programming/tree/e8f5b202e6b12709a72df5df3908a4700ca5517d/CH9/build/IP/pix_clk
- Upstream `video_out_clock.vhd` (tyto2): https://github.com/amb5l/tyto2/blob/04459acec10296289c5558b419cc4fdd94544bf1/src/common/video/xilinx/7series/video_out_clock.vhd
- DS181 v1.27.1 "Artix 7 FPGAs Data Sheet: DC and AC Switching Characteristics", Tables 15, 32, 37.
- UG472 v1.14 "7 Series FPGAs Clocking Resources", chapter 3, Table 3-7.
