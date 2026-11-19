# R3: The scaler (ascal) at equal frame rates

Subject: how `M2M/vhdl/av_pipeline/ascal.vhd` (TEMLIB 2018 to 2020, 2915 lines) behaves when the HDMI frame rate equals the C64's frame rate, what it offers for that case, and what a genlock or an exactly-equal-rate mode has to respect. Line numbers refer to `M2M/vhdl/av_pipeline/ascal.vhd` unless another file is named. Each statement is marked **[code]** (read in the source), **[sim]** (confirmed by the GHDL experiment in section 11) or **[inference]** (derived, not directly checked).

## 0. Summary

1. **Our ascal runs in direct mode (one frame buffer), not triple buffering.** The firmware writes only the mode words 0 to 4 (`M2M$ASCAL_NEAREST` ... `M2M$ASCAL_POLYPHASE`, `CORE/m2m-rom/m2m-rom.asm` `HDMI_FLT_TABLE`, about line 1644), never `M2M$ASCAL_TRIPLEBUF` (`0x0008`, `M2M/rom/sysdef.asm:130`), and the register stores exactly what is written (`M2M/vhdl/QNICE/qnice.vhd:610-611`). So `mode(3) = '0'` and every buffer index is forced to 0 (1946-1952). **[code]** Today's 50.000 Hz output therefore does not drop or repeat whole frames: it reads the buffer that the core is writing, and about every 8 s (PAL, 1/0.124 Hz) the read pointer and the write pointer cross inside the picture, which is a tear line that moves through the image. Flicker-free exists to prevent exactly that crossing. **[inference from the code]**
2. **Triple buffering** (`mode(3) = '1'`) decides once per output frame, at the falling edge of the output vsync (output line `vsend`, pixel `hsstart`), whether a newer input frame is complete; the input side switches buffers at the rising edge of the input vsync. At exactly equal frame periods and constant phase every input frame is shown exactly once, with a latency of 1 to 2 frames depending on the phase. The decision point is one specific output clock edge; only an input event that falls within the capture uncertainty of one flip-flop around it (sub-nanosecond, call it plus or minus one output clock to be safe) can flip from frame to frame. **[code + sim]**
3. **Direct mode** at equal rates is tear-free if, for every input line, the output fetches it after the core wrote it and before the core writes it again one frame later. Because input and output sweep the picture at different speeds, the gap changes across the picture by `A - B` (output image duration minus input image duration): 1.89 ms in PAL 720p, 1.12 ms in PAL 576p 4:3, 0.16 ms in NTSC 720p, -0.61 ms in NTSC 480p 4:3. Everything else of the frame is a safe phase. A free-running phase at exactly equal rates has a chance of about `(|A - B| + margin) / T` (PAL 720p: about 10 %) to sit in the unsafe zone, which then gives a **static** tear line. Direct mode therefore needs a phase controller; it then gives the lowest latency (PAL 720p: about 0.3 ms at the top of the picture to 2.2 ms at the bottom). **[inference from the code]**
4. **`htotal` and `vtotal` may be changed at run time, line by line or frame by frame.** Inside ascal they are used only by the wrap of the output counters (2679, 2683). The changed pixel or line lands at the end of the horizontal or vertical back porch; the pixel pipeline, the line buffers and the moment at which a line is fetched (the start of hsync) are unaffected. **[code + sim]** They are sampled every clock without synchronizer (1878, 1885), so the controller must sit in the output (HDMI) clock domain.
5. **No VRR in our version** (nor in the MiSTer copy `CORE/C64_MiSTerMEGA65/sys/ascal.vhd`). The current upstream ascal has it: the output waits in the vertical front porch until the input frame ends and then jumps straight to vsync start. That is a ready-made line-granular genlock. **[code, upstream]**
6. **`hdmi_flicker_free.vhd` is a usable phase detector for direct mode**: it samples the core's last write address (HyperRAM word address) at the moment the output fetches the first burst of a frame. Linear over the input's active lines (resolution one 128-byte burst, 7.1 µs PAL), saturated during the input's vertical blanking, valid only in direct mode. **[code]**
7. **Memory traffic** does not depend on the output totals; reads scale with the output frame rate (one fetch per input line per output frame). PAL: about 15.6 MB/s writes plus 15.7 MB/s reads, NTSC about 19.1 plus 19.3 MB/s. **[code + inference]**

## 1. Our configuration (question 8)

`M2M/vhdl/av_pipeline/digital_pipeline.vhd:330-462` instantiates ascal with:

| Generic | Value | Meaning here |
|---|---|---|
| `RAMBASE` | 0 | buffer 0 at HyperRAM (R3) or SDRAM (R4 to R6) address 0 |
| `RAMSIZE` | `2**f_log2(G_VGA_DX * G_VGA_DY * 3)` = 2 MB (720 x 540 x 3 rounded up) | spacing of the three buffers; one C64 frame needs only 311 kB (PAL) or 320 kB (NTSC) |
| `INTER` | false | progressive only, `i_inter` is always 0 |
| `HEADER` | false | no image header in front of the frame |
| `DOWNSCALE` | false, `DOWNSCALE_NN` true | upscaling only |
| `FRAC` | 6 | |
| `OHRES` / `IHRES` | 2048 / 1024 | |
| `N_DW` / `N_AW` / `N_BURST` | 128 / 19 / 128 | 128-bit Avalon words, 128-byte bursts (8 beats) |

Ports: `i_ce` = the core's pixel clock enable after `crop.vhd`, `i_de = not (hblank or vblank)`, `o_ce = '1'`, `iauto = '1'` (automatic input size), `run = '1'`, `freeze = '0'`, `mode = qnice_ascal_mode_i`, `o_lltune => open`, output timing from the selected `video_modes_pkg` record (`htotal = H_PIXELS + H_FP + H_PULSE + H_BP` and so on, digital_pipeline.vhd:193-200), `hmin`/`hmax`/`vmin`/`vmax` from the aspect logic (222-272). Avalon clock is `hr_clk` (100 MHz). Behind ascal: `avm_decrease` to 16-bit words (22-bit word address), then on R3 the HyperRAM arbiter shared with the core (REU, CRT, drives) and QNICE (`M2M/vhdl/framework.vhd:1021-1059`), on R4 to R6 an SDRAM that ascal has for itself (`framework.vhd:1061-1130`).

The `mode` bits as used: `mode(2 downto 0)` = 0 (nearest, "No Filter"), 2 (sharp bilinear), 3 (bicubic) or 4 (polyphase, the other five filters); `mode(3) = '0'` (direct, single buffer); `mode(4) = '0'` (unused). **[code]** The VHDL ports `qnice_ascal_triplebuf_o` and `qnice_ascal_polyphase_o` of `MEGA65_Core` are tied to `'0'` (`CORE/vhdl/mega65.vhd:1243-1244`) and only matter for `ASCAL_USAGE = 2`; we use `ASCAL_USAGE = 1` (`CORE/vhdl/config.vhd:286`).

Input geometry seen by ascal (`CORE/C64_MiSTerMEGA65/rtl/video_sync.vhd`, `doc/ntsc.md`): PAL 382 x 270 active of 504 x 312 dots, active lines 28 to 297, vsync lines 307 to 311 (rising at dot 10 of line 307, i.e. 9 lines after the last active line); NTSC 404 x 250 active of 520 x 263, active lines 13 to 262, vsync lines 0 to 4 (right after the last active line). Input line 63.944 µs (PAL) or 63.556 µs (NTSC); frame 19.9504 ms (50.124291 Hz) or 16.7151 ms (59.826105 Hz).

## 2. Buffering (question 1)

### 2.1 Mode bits

Header comment (78-92): `MODE[2:0]` selects the interpolator (000 nearest, 001 bilinear, 010 sharp bilinear, 011 bicubic, 100 polyphase); `MODE[3]`: `0 : Direct. Single framebuffer.`, `1 : Triple buffering`; `MODE[4] : TBD`. `RAMSIZE` is the RAM for one frame buffer, "needs x3 if triple-buffering", power of two (97-98).

### 2.2 Buffer bookkeeping (output clock domain)

All buffer indices live in the output clock domain: `o_ibuf0/1` (buffer being written), `o_obuf0/1` (buffer being shown), `o_bufup0/1` (a completed frame waits to be shown), index 0 for even fields, 1 for odd fields; with progressive input index 1 is a copy of index 0 (1940-1944). The two helper functions (391-405):

```vhdl
FUNCTION buf_next(a,b : natural RANGE 0 TO 2; freeze : std_logic := '0') RETURN natural IS
BEGIN
  IF (freeze='1') THEN RETURN a; END IF;
  IF (a=0 AND b=1) OR (a=1 AND b=0) THEN RETURN 2; END IF;
  IF (a=1 AND b=2) OR (a=2 AND b=1) THEN RETURN 0; END IF;
  RETURN 1;
END FUNCTION;
-- buf_offset(b) = base, base + size, base + 2*size for b = 0, 1, 2
```

`buf_next(a, b)` returns the third buffer, the one that is neither `a` nor `b`. The selection logic (process `Scalaire`, 1896-1952):

```vhdl
o_iendframe0<=i_endframe0; -- <ASYNC>
o_iendframe02<=o_iendframe0;
IF o_iendframe0='1' AND o_iendframe02='0' THEN      -- input frame complete
  o_ibuf0<=buf_next(o_ibuf0,o_obuf0,o_freeze);       -- write the next one into the free buffer
  o_bufup0<='1';
END IF;
...
IF o_vsv(1)='1' AND o_vsv(0)='0' AND o_bufup0='1' THEN  -- output VS falling edge
  o_obuf0<=buf_next(o_obuf0,o_ibuf0,o_freeze);         -- show the latest complete frame
  o_bufup0<='0';
END IF;
...
IF o_vsv(1)='1' AND o_vsv(0)='0' AND                 -- both in the same clock
  o_iendframe0='1' AND o_iendframe02='0' THEN
  o_bufup0<='0';
  o_obuf0<=o_ibuf0;                                  -- show the frame that just completed
END IF;
...
IF o_mode(3)='0' THEN                                -- direct mode
  o_obuf0<=0; o_obuf1<=0; o_ibuf0<=0; o_ibuf1<=0;
END IF;
```

**The input decision.** The input side (`InAT`, 1115-1561) writes relative addresses only: `i_adrsi` restarts at 0 at the first `i_de` after a rising `i_vs` (1194-1215), and grows by one burst (`N_BURST`) per burst plus a partial burst at the end of each line. The input end of frame is `i_endframe0 <= i_vs AND (NOT i_inter OR i_flm)` (1221), registered in the input clock when `i_pce = '1'`, i.e. the raw `i_vs` level; its rising edge is the end of the input frame. The output clock domain captures it with one flip-flop (`o_iendframe0`), detects the edge with a second one, and at that clock moves `o_ibuf0` to the free buffer. The physical address of a write burst is formed in the Avalon clock domain when the burst starts (`sIDLE` to `sWRITE`, 1711-1729), from `avl_i_offset0 <= buf_offset(o_ibuf0, RAMBASE, RAMSIZE)`, which is copied from the output domain every Avalon clock without synchronizer (1695-1696). So the buffer of the next input frame is decided at the output clock edge that sees the input vsync rise, and takes effect for every burst the Avalon side starts a few clocks later. The first burst of the new frame comes only with its first active line (PAL 33 input lines, NTSC 13 lines after the vsync edge), so there is no ambiguity. **[code]**

**The output decision.** At the falling edge of the output vsync as seen by `Scalaire` (`o_vsv(1) = '1' and o_vsv(0) = '0'`, 1915), i.e. two output clocks after the output counters reach pixel `hsstart` of line `vsend` (`o_vsv(0)`, 2698-2700), `o_obuf0` moves to the latest complete frame, if `o_bufup0` says there is one. The Avalon side copies `avl_o_offset0 <= buf_offset(o_obuf0, ...)` every clock (1683-1687) and adds it to each read burst (1745-1750). The first read of an output frame is the preload of input lines 0 and 1, started at the hsync of the line on which the lead counter `o_vcpt_pre3` equals `vmin` (2011-2015), i.e. 3 output lines before line `vmin` is displayed. Between the buffer switch (line `vsend`) and that first read there are `vtotal - vsend + vmin - 3` lines (17 in 720p, 36 in 576p, 27 in 480p). **[code]**

`o_ihsize`/`o_ivsize` (input image size for the output side) are taken over at the same output vsync falling edge, when `o_bufup1 = '1'` (1919-1926). **[code]**

### 2.3 Clock domain crossings

| From | To | Signal | How |
|---|---|---|---|
| input | output | `i_endframe0/1` | 1 flip-flop (`o_iendframe0`), then edge detect (1900-1912) |
| input | output | `i_inter`, `i_hrsize`, `i_vrsize`, `i_hdown`, `i_vdown` | plain register, sizes only at the output vsync falling edge (1922-1925) |
| output | input | `o_hsize`, `o_vsize` | plain register (1296-1297), only for downscaling |
| input | Avalon | write request | toggle `i_write`, 2 flip-flops + edge (1660-1667), address and flags taken at the pulse, at least 5 input clocks between requests (1549-1558) |
| output | Avalon | read request | toggle `o_read`, 2 flip-flops + edge (1670-1674), `o_adrs`/`o_rline` copied every clock |
| output | Avalon | `o_ibuf*`, `o_obuf*` | copied every clock without synchronizer (1683-1696) |
| output | Avalon | output vsync `o_vsv(0)` | 2 flip-flops; the falling edge resets the read FIFO write pointer `avl_wad` (1677-1678, 1771-1773) |
| Avalon | output | read accepted / burst data complete | toggles `avl_readack`, `avl_readdataack`, 2 flip-flops (1995-2001) |
| data | | `i_dpram` (input to Avalon), `o_dpram` (Avalon to output) | dual-clock RAMs of two bursts each |

## 3. Equal frame periods, constant phase, triple buffering (question 2)

Define two events per frame:

- `E`: the output clock edge at which `Scalaire` sees `o_iendframe0 = '1' and o_iendframe02 = '0'`. It is two output clocks after the first output clock edge that samples `i_endframe0 = '1'`; `i_endframe0` itself rises at the first input clock edge with `i_pce = '1'` after `i_vs` rose.
- `S`: the output clock edge at which `Scalaire` sees `o_vsv(1) = '1' and o_vsv(0) = '0'`: output line `vsend`, pixel `hsstart`, plus 2 clocks. The `o_vs` port falls 10 output clocks later (`o_vs <= o_vsv(9)`, 2853).

**Rule [code + sim]:** if `E` comes before `S` or in the same clock, the frame that just ended is shown from the output frame that begins after `S`; if `E` comes after `S`, it is shown one output frame later. With exactly equal frame periods, `phi = S - E` (modulo the frame period `T`) is constant, so the same branch is taken every frame and **every input frame is shown exactly once**. A constant phase alone is enough; no particular phase is required.

**Critical window [code, inference for the width]:** the boundary is a single output clock edge. Both clocks come from the same 100 MHz oscillator; at exactly equal frame periods the input edge lands at the same place relative to the output clock edges in every frame, so the decision is reproducible. Only if the input edge falls within the setup/hold aperture of the capturing flip-flop plus the clock jitter (well below 1 ns for MMCM clocks) can the capture move by one output clock from frame to frame; then the display alternates between "shown at once" and "shown one frame later", which is a frame shown twice followed by a frame skipped. Treat the window as plus or minus one output clock around the boundary to be safe: 13.4 ns at 74.25 MHz, 37 ns at 27 MHz. Outside of it nothing random happens.

**When the periods are not exactly equal [code + sim]:** the phase walks by `T` times the frequency error per frame (PAL 720p at the nearest standard-total clock, +133 ppm: 2.65 µs per frame) and crosses the boundary once per `1 / (f_out - f_in)` (150 s); each crossing costs exactly one repeated frame (output faster) or one skipped frame (output slower), cleanly, because the walk per frame is far larger than the jitter.

**Safest phase.** Any `phi` away from the boundary is safe if the rates are exactly equal. With a control loop, the choice is between robustness and latency:

- Maximum tolerance: `phi` near `T / 2` (input frame ends about half a frame before the output vsync ends): plus or minus 10 ms (PAL) of slack for phase errors.
- Minimum latency: `phi` small but clearly positive, e.g. 2 to 4 output lines (50 to 100 µs in 720p). In words: the output vsync ends a few output lines after the input vsync begins; the output image then starts `vtotal - vsend + vmin` output lines after `S` (720p: 20 lines = 0.53 ms; 576p: 39 lines = 1.25 ms; 480p: 30 lines = 0.96 ms).

**Latency with triple buffering [inference, computed with the raw frame rates]:** time from a pixel entering ascal to the output line that first shows it (without HDMI encoder and display), for the first (`L0`) and last (`Lmax`) active input line. `phi` ranges from just above 0 to just below `T`.

| Mode | output line | `A - B` | `S` to image start | `L0` | `Lmax` | best (`phi` to 0) | worst (`phi` to `T`) |
|---|---|---|---|---|---|---|---|
| PAL 720p | 26.601 µs | +1.888 ms | 0.532 ms | 18.37 ms + `phi` | 20.25 ms + `phi` | 18.4 to 20.3 ms | 38.3 to 40.2 ms |
| PAL 576p 4:3 | 31.921 µs | +1.122 ms | 1.245 ms | 19.09 ms + `phi` | 20.20 ms + `phi` | 19.1 to 20.2 ms | 39.0 to 40.2 ms |
| PAL 576p 5:4 (`vmin` 18) | 31.921 µs | +0.004 ms | 1.819 ms | 19.66 ms + `phi` | 19.66 ms + `phi` | 19.7 ms | 39.6 ms |
| NTSC 720p | 22.287 µs | +0.158 ms | 0.446 ms | 16.33 ms + `phi` | 16.49 ms + `phi` | 16.3 to 16.5 ms | 33.0 to 33.2 ms |
| NTSC 480p 4:3 | 31.838 µs | -0.607 ms | 0.955 ms | 16.84 ms + `phi` | 16.24 ms + `phi` | 16.2 to 16.8 ms | 33.0 to 33.6 ms |

The fixed part is large because the frame is complete only at the input vsync (PAL: 279 input lines after the start of the first active line, of which 9 lines are bottom blanking).

## 4. Direct mode and low lag (question 3)

### 4.1 Tear-free condition

In direct mode input and output use buffer 0 (1946-1952); nothing coordinates them. **[code]** For input line `L` let `Delta(L)` = (time the output fetches line `L`) minus (time line `L` of the current frame is completely in memory). The picture is tear-free if `0 < Delta(L) < T` for all active lines, with margins. **[inference]**

- The output fetches an input line at the start of hsync (`o_hsv` rising edge, 2011) of an output line about two lines before it is displayed (the vertical state machine works on `o_vcpt_pre2`, 2059; the preload of lines 0 and 1 on `o_vcpt_pre3`, 2012). For the 4-tap filters (bicubic, polyphase) the newest line in the four line buffers is about 2 input lines ahead of the displayed position. **[code, lookahead in lines is inference]**
- The input writes a line in 128-byte bursts while it arrives (one burst per 42.7 pixels at 24 bpp) and the rest at the end of the line (1508-1540), plus the Avalon latency of the shared memory. **[code]**
- `Delta(L)` changes linearly across the picture by `A - B` in total (`A` = output image duration `(vmax - vmin + 1)` output lines, `B` = input image duration 270 or 250 input lines; numbers in the table of section 3). For `A > B` ("expand": 720p, 576p 4:3, NTSC 720p) the gap is smallest at the top; for `A < B` (NTSC 480p) at the bottom.

So the usable phase range is about `T - |A - B| - margins`, at least 89 % of the frame in every mode. Lowest latency: the minimal gap (at the top or at the bottom of the picture) a few input lines; then the latency is about 0.3 ms at the critical end and grows by `A - B` towards the other end (PAL 720p: 0.3 ms at the top, 2.2 ms at the bottom). MiSTer uses 4 input lines (section 4.3), our flicker-free 7 to 14 lines (section 9). **[inference]**

At exactly equal rates and a phase that is not controlled, the phase is arbitrary but constant: the chance that it lies in the tear zone is about `(|A - B| + margin) / T`, about 10 % in PAL 720p, 6 % in PAL 576p 4:3, 1 to 3 % in NTSC 720p; and then the tear line stands still in the picture. Direct mode at equal rates therefore needs a defined phase (a controller, or a deterministic start), triple buffering does not. **[inference]**

### 4.2 `o_lltune`

Lines 2903-2912:

```vhdl
o_lltune<=(0 => i_vss,
           1 => i_pde,
           2 => i_inter,
           3 => i_flm,
           4 => o_vss,
           5 => i_pce,
           6 => i_clk,
           7 => o_clk,
           OTHERS =>'0');
```

| Bit | Signal | Domain | Meaning |
|---|---|---|---|
| 0 | `i_vss` | input, updated when `i_pce = '1'` (1224) | input vertical window: `i_vcpt` within `i_vmin` to `i_vmax`; rises one pixel after the first `i_de` of a frame, falls 16 pixels after the last active line |
| 1 | `i_pde` | input | `i_de` registered once |
| 2 | `i_inter` | input | interlace detected (always 0 here) |
| 3 | `i_flm` | input | field of the current frame |
| 4 | `o_vss` | output, updated when `o_ce = '1'` (2702) | output image window two lines early: `o_vcpt_pre2` within `vmin` to `vmax`; rises at the start of displayed line `vmin - 2`, falls at the start of displayed line `vmax - 1` |
| 5 | `i_pce` | input | `i_ce` registered once |
| 6 | `i_clk` | | the input clock itself |
| 7 | `o_clk` | | the output clock itself |
| 8 to 15 | 0 | | |

All bits are raw; the receiver synchronizes them. The header of `CORE/C64_MiSTerMEGA65/sys/pll_hdmi_adj.vhd` lists bits 0 and 1 the other way round; its code uses bit 0 as the vertical window and bit 1 as DE, like ascal. Bits 6 and 7 are clocks: `pll_hdmi_adj` clocks a process with bit 6. In our design `o_lltune` is left open.

### 4.3 How MiSTer uses it

`sys_top.v` (local copy line 684, upstream 791): `.mode({~lowlat, LFB_EN ? LFB_FLT : |scaler_flt, 2'b00})`. MiSTer's normal mode is triple buffering; its low-latency mode (`lowlat`, set by the ARM side) is direct mode plus `pll_hdmi_adj` (`.llena(lowlat)`, `.lltune(...)`, clocked by the 50 MHz board clock). **[code]**

`pll_hdmi_adj.vhd`:

1. Input clock domain (clocked by `lltune(6)`, enabled by `lltune(5)`): measures the input line length in pixels and delays `i_vss` by 4 input lines (`i_vss_delay`, 91-118).
2. 50 MHz domain: synchronizes the delayed input window and `o_vss` with two flip-flops, measures both periods over two frames (toggles `itog`/`otog`, so interlaced fields pair up), `udiff` = output minus input period in 50 MHz ticks, and the phase `offset` = time from the output window start to the delayed input window start if the output image lasts at least as long as the input image ("expand"), otherwise between the window ends (122-233).
3. Converts both errors to a sign and a bit position (`tune_freq`, `tune_phase`) and steps the fractional multiplier of the HDMI PLL by `mfrac_ref >> off_v` (relative steps of 2 to the power of minus 4 to minus 31), once every fourth measurement. Frequency steps move the reference (`mfrac_ref`); once the frequency error has stayed below 2 to the power of minus 16 for 10 steps it switches to 10 phase steps, which only offset the PLL temporarily from the reference (a short frequency offset that moves the phase), then back to frequency. It snoops the regular PLL reconfiguration writes to learn the base value and restores it when `llena` drops. `locked` when both errors are below 2 to the power of minus 18 (257-428).

Target: the output image window starts when the input has written 4 lines (expand case), i.e. the output reads input lines 0 and 1 while line 4 arrives. That is MiSTer's tear-free margin for direct mode. **[code]**

## 5. Variable refresh rate (question 4)

- Our `M2M/vhdl/av_pipeline/ascal.vhd`: no VRR (no port, generic or logic). **[code]**
- `CORE/C64_MiSTerMEGA65/sys/ascal.vhd` (2564 lines, an older MiSTer version): no VRR. **[code]**
- Current upstream (`MiSTer-devel/Template_MiSTer`, `sys/ascal.vhd`, 3049 lines): yes. Ports `vrr : IN std_logic := '0'` and `vrrmax : IN natural RANGE 0 TO 4095 := 0` (upstream 224-225); `sys_top.v` drives `.vrr(vrr_mode)` and `.vrrmax(HEIGHT + VBP + VS + 1)`, with `vtotal` as usual (upstream sys_top 781-788). Other upstream additions: `bob_deint`, `swblack` (three black frames after a resolution change). The buffer logic is the same as ours plus a pulse `o_isync` at the detected input frame end. **[code]**

How upstream VRR works (upstream ascal 1913-1936 and 2770-2843) **[code]**:

```vhdl
IF o_vcpt_pre3+1>=o_vtotal THEN
  o_vcpt_pre3<=0;
ELSIF o_vrr_sync2 THEN
  o_vcpt_pre3<=o_vsstart;           -- cut the front porch: jump to vsync start
  o_sync<=false;
ELSE
  o_vcpt_pre3<=(o_vcpt_pre3+1) MOD 4096;
END IF;
...
IF o_isync2='1' THEN                -- input frame end (2 clocks after detection)
  o_vcpt_sync<=0;                   -- output lines since the last input frame end
  o_sync_max<=o_vrr_max2;           -- that count was below vrrmax
  IF o_vrr_min2 THEN o_sync<=true; END iF;   -- that count was below vtotal
END IF;
o_vcpt2<=o_vcpt_pre3;
o_vrr_sync<=(o_vrr='1' AND (o_sync OR o_sync_max) AND o_vcpt2>=o_vdisp AND o_vcpt2<o_vsstart);
```

`vtotal` describes the longest frame (lowest refresh rate, long front porch). When an input frame ends, the output finishes its current line and, if its lead counter is in the front porch (`vdisp` to `vsstart - 1`), jumps to `vsstart`; if it is still in the picture, the jump happens as soon as it reaches `vdisp`. The jump is on the lead counter `o_vcpt_pre3`; all derived timing (the line fetch on `o_vcpt_pre3`/`o_vcpt_pre2`, `o_vss`, `o_vsv`) follows three lines later, consistently. Since the buffer switch happens at the end of the vsync that the jump starts, and `o_bufup` was set by the same input frame end, the frame just completed is always the one shown: latency is fixed at about one output line plus 3 lines plus vsync plus back porch after the input frame end. The output frame length is an integer number of lines and alternates between the two neighbours of `T / output line` (e.g. 750 and 751 lines), which a display has to accept (VRR or tolerant). The input frame end must arrive while the lead counter is in the front porch, i.e. the nominal `vtotal` frame must be longer than the input frame with some lines of slack, otherwise an arrival after `vsstart` makes the next frame short. **[inference for the operating conditions]**

Porting it to our version is small: the two ports, `o_isync` at the edge detection, the line counter `o_vcpt_sync`, the comparisons and the jump. **[inference]**

## 6. Output timing generator (question 5)

Counters (`OSWEEP`, 2674-2720), all advanced when `o_ce = '1'` (always here):

```vhdl
IF o_hcpt+1<o_htotal THEN
  o_hcpt<=(o_hcpt+1) MOD 4096;
ELSE
  o_hcpt<=0;
  IF o_vcpt_pre3+1>=o_vtotal THEN
    o_vcpt_pre3<=0;
  ELSE
    o_vcpt_pre3<=(o_vcpt_pre3+1) MOD 4096;
  END IF;
  o_vcpt_pre2<=o_vcpt_pre3;
  o_vcpt_pre<=o_vcpt_pre2;
  o_vcpt<=o_vcpt_pre;
END IF;
```

`o_vcpt_pre3` is the vertical lead counter; `o_vcpt_pre2`, `o_vcpt_pre` and `o_vcpt` are the same sequence delayed by 1, 2 and 3 lines. `o_vcpt`/`o_hcpt` produce DE, the picture window, hsync and vsync (`o_dev(0)`, `o_pev(0)`, `o_hsv(0)`, `o_vsv(0)`, 2693-2700), which pass a 10-stage delay line (`o_hsv(1 TO 9)` ...) to the ports (`o_hs <= o_hsv(9)` ..., 2852-2859); `o_vcpt_pre3`/`o_vcpt_pre2`/`o_vcpt_pre` drive the line fetch and the vertical interpolation (2012, 2019, 2059) and `o_vss`.

Sampling: `htotal`, `hsstart`, `hsend`, `hdisp`, `hmin`, `hmax`, `vtotal`, `vsstart`, `vsend`, `vdisp`, `vmin`, `vmax` are copied into `o_*` registers **every output clock** without synchronizer (`-- <ASYNC> ?`, 1878-1890); `o_hsize`/`o_vsize` follow one clock later. **[code]**

Where each one is used **[code, from a search of all uses]**:

- `o_htotal`: only `o_hcpt+1<o_htotal` (2679).
- `o_vtotal`: only `o_vcpt_pre3+1>=o_vtotal` (2683).
- `o_hsstart`/`o_hsend`: hsync (2697) and vsync start/end pixel (2698-2700); the rising edge of `o_hsv` starts the line fetch (2011).
- `o_vsstart`/`o_vsend`: vsync (2698-2700); the vsync falling edge switches the shown buffer (1915) and resets the Avalon read FIFO pointer (1771).
- `o_hdisp`/`o_vdisp`: DE and `o_vbl` (2693-2694).
- `o_hmin`/`o_hmax`/`o_vmin`/`o_vmax`: picture window, scale factors (`o_hsize`, `o_vsize`), the vertical and horizontal accumulators, line buffer read addresses (`o_v_hmin_adj`, 2732) and the fetch triggers.

Consequences:

- **Changing `htotal` from line to line (e.g. 1980/1981) or stretching a single line is harmless to ascal.** The extra or missing pixel is at the end of the line, after `hsend` (horizontal back porch). Everything else in a line is timed from the line start or from `hsstart` and does not see it. The value is compared every clock with `>=`/`<`, so even a change at the very end of a line only decides whether that line gets the old or the new length; no glitch is possible. **[code + sim]**
- **Changing `vtotal` by a line is equally harmless.** The extra or missing line is the last line of the lead counter, i.e. at the end of the vertical back porch; in triple mode the buffer switch at `vsend` still happens before the first fetch at `vmin - 3` as long as the back porch keeps at least 3 lines plus a margin. **[code + sim]**
- What changes if the totals differ from the mode's nominal values by a few counts: inside ascal only the frame and line period. Outside of ascal: the display has to accept it (R4), and the HDMI encoder sees slightly different blanking lengths (`vga_to_hdmi.vhd` puts data islands into the blanking; one pixel more or less per line leaves the 220-pixel (720p) or 60-pixel (480p) back porch practically unchanged). **[inference]**
- The registers have no synchronizer: the controller must change `htotal`/`vtotal` in the output clock domain (synchronous to `hdmi_clk`), otherwise a multi-bit change can be sampled half-way. A practical moment is right after the falling edge of `o_hs` at the port (that is about 200 clocks before the line end in 720p, about 60 in 576p and 480p). **[code + inference]**
- `hsstart`, `hsend`, `vsstart`, `vsend`, `hdisp`, `vdisp` and the window must stay constant: they move the fetch trigger, the buffer switch and the picture.

## 7. Input side (question 6)

**Frame start and size [code]** (all on `i_pce`, 1176-1464):

- A rising `i_vs` sets `i_sof` (1194-1196). The next rising `i_de` with `i_sof = '1'` resets the line counter `i_vcpt` and the write address `i_adrsi` (1202-1215).
- Horizontal: `i_hcpt` restarts at every rising `i_de`; at the falling `i_de` its value is the width minus 1 (`i_himax`, 1227-1236). Vertical: `i_vcpt` advances 16 pixels after each falling `i_de` (`i_de_delay = 16`, 1447-1453); its value at each rising `i_de` is `i_vimax` (the last line index once the frame is done).
- With `iauto = '1'`: `i_hmax <= i_himax` continuously, `i_vmax <= i_vimax` at each rising `i_vs` (1238-1245); `i_hsize`/`i_vsize` follow (1279-1294). The write burst count per line `i_hburst` (9 in PAL, 10 in NTSC at 24 bpp) follows `i_hrsize` (1261-1267).
- Input end of frame: `i_endframe0/1` = registered `i_vs` (1221-1222).

**Discontinuities [code + inference]:** ascal has no notion of a lost or broken input. Each rising `i_vs` followed by a `i_de` starts a new frame at address 0; sizes are re-measured continuously and reach the output side at the next output vsync falling edge after an input frame end (1919-1926). Consequences:

- A geometry change (PAL/NTSC: 382 x 270 to 404 x 250, stride 1152 to 1280 bytes) gives at most one output frame that interprets new data with the old size and stride, then the picture is correct. MiSTer's newer `swblack` blanks three frames in that case.
- A core reset that restarts the video timing shifts the input phase: in direct mode the tear position jumps (and moves until a controller has caught up); in triple mode at most one frame is repeated or skipped, then the new constant phase holds.
- If the input stops (no vsync), direct mode keeps showing buffer 0 as it is; triple mode keeps showing the last complete frame. The output timing never depends on the input.

**`freeze` [code]:** `i_freeze` (input clock, 1145) blocks all write requests and header writes (1482-1540); `o_freeze` makes `buf_next` return its first argument, so neither `o_ibuf` nor `o_obuf` change (391-397). The picture stands still. Not used here (`'0'`).

**Signals that mark "input frame complete" [code]:**

- `i_endframe0` (input clock): rising edge = input frame end.
- In the output clock: `o_iendframe0 = '1' and o_iendframe02 = '0'` is the exact event the triple buffer acts on (upstream names it `o_isync`).
- Already on a port: `o_lltune(0)` (`i_vss`, input picture window) and `o_lltune(4)` (`o_vss`, output picture window two lines early); these are the signals MiSTer's phase detector uses.
- For a phase detector outside ascal, synchronizing the core's `video_vs` (or the end of the last DE line) into the HDMI clock domain with two flip-flops is equivalent at frame-level precision. **[inference]**

## 8. Memory bandwidth (question 7)

**[code]** Writes: per input frame one pass of `i_hburst` bursts per active line. Reads: in `sHSYNC` (2042-2083) the vertical accumulator advances; a line is fetched (`o_hburst` bursts) only when the source line changes (`o_vcarrym`) or during the two-line preload (`o_fload`). When upscaling every input line is therefore fetched once per output frame, plus the preload. Nothing in the read or write path depends on `htotal` or `vtotal`. **[code]**

**[inference, numbers]** PAL: 270 lines x 9 bursts x 128 bytes = 311 kB per frame; writes 15.6 MB/s, reads about 15.7 MB/s times `f_out / f_in`. NTSC: 250 x 10 x 128 = 320 kB; 19.1 MB/s writes, about 19.3 MB/s reads. A mode with equal frame rates changes the read traffic by +0.25 % (PAL) or -0.19 % (NTSC) against today's 50.000 / 59.94 Hz. The pattern stays the same: the 9 or 10 read bursts of one input line are requested at the hsync of the output line before they are needed, i.e. every 2.67 (PAL 720p) output lines. On R4 to R6 ascal has the SDRAM to itself, on R3 it shares the HyperRAM with REU, CRT and drives.

## 9. `hdmi_flicker_free.vhd` as a phase detector (question 8)

`M2M/vhdl/hdmi_flicker_free.vhd`, instantiated in `M2M/vhdl/av_pipeline/av_pipeline.vhd:637-649` on the narrow (16-bit word) side of `digital_pipeline`, i.e. on ascal's own Avalon traffic before any arbiter, in the 100 MHz `hr_clk` domain:

```vhdl
if hr_write_i = '1' then last_core_address <= hr_address_i; end if;  -- the core writes
if hr_read_i  = '1' then last_hdmi_address <= hr_address_i; end if;  -- the HDMI side reads
...
if last_hdmi_address = 0 then
   last_diff <= last_core_address;   -- core write position while the HDMI read is at 0
end if;
...
if last_diff < G_THRESHOLD_LOW  then low_o  <= '1'; end if;   -- core too slow
if last_diff > G_THRESHOLD_HIGH then high_o <= '1'; end if;   -- core too fast
```

**What it measures [code]:** the HyperRAM word address of the core's most recent write burst while the output's most recent read burst is the one at address 0. The read at address 0 is the first burst of the two-line preload, issued at hsstart of the output line 3 lines before `vmin`, once per output frame. So `last_diff` is the input write position at the moment the output starts reading a frame. `G_THRESHOLD_LOW = 0x1000`, `G_THRESHOLD_HIGH = 0x2000` words; one input line is 1152 bytes = 576 words (PAL; 1280 bytes = 640 words NTSC), so the band is 7.1 to 14.2 input lines (PAL). `mega65.vhd` (`hr_core_speed`, around line 650) switches the core between its original and its flicker-free clock on `hr_high_i`/`hr_low_i`.

**As a phase detector for a genlock [inference]:**

- Characteristic: linear in the phase while the output's frame start lies within the input's active lines (0 to about 155,000 words), resolution one burst = 64 words = 1/9 input line = 7.1 µs (PAL), one sample per output frame. During the input's vertical blanking (42 lines PAL, 13 lines NTSC) it saturates at the address of the last burst of the last line.
- It is a ready-made, already synthesized measurement of exactly the quantity direct mode cares about (the gap between writer and reader at the top of the picture). A genlock that adjusts the HDMI side can use `last_diff` with a set point inside the linear range (e.g. the middle of today's band, about 10 input lines) and a proportional output instead of the two thresholds.
- Limits: (1) it works only in direct mode: with triple buffering the addresses carry the buffer offsets (`RAMSIZE` = 2 MB = 0x100000 words per buffer), `last_hdmi_address = 0` only matches when buffer 0 is shown, and the difference is meaningless; (2) it measures only the top of the picture, not the gap at the bottom (which matters for NTSC 480p, where the output reader gains on the writer, `A < B`); (3) it lives in the HyperRAM clock domain, so a controller in the HDMI clock domain needs a CDC for it; (4) the resolution of 7 µs is coarse for a line-length genlock (one 720p pixel is 13.4 ns), so it suits a slow outer loop, not a fine phase lock.
- A finer detector: count output clocks from the output's `o_vss` rising edge (or `o_vs`) to the synchronized input vsync (or `o_lltune(0)` rising), in the HDMI clock domain. Resolution one output clock, plus or minus one clock of synchronizer uncertainty.

## 10. What a genlock or an exactly-equal-rate mode has to respect

1. **Pick the buffering mode first.** Triple buffering: any constant phase works, the controller only needs to keep the phase away from one boundary (and the latency is 1 to 2 frames). Direct mode (today's setting): the phase must be held inside a window of at least 89 % of the frame, but the latency is a fraction of a frame.
2. **Triple buffering is not available on R3 as configured.** Three buffers at `RAMSIZE` spacing need 6 MB at `RAMBASE` 0; the M2M region of the HyperRAM map is 3 MB (`C_HMAP_CRT = x"0180"`, `CORE/vhdl/globals.vhd:142-143`), so buffer 2 (4 MB to 4.3 MB) would overwrite the start of the SIMCRT pool. The guard assertion in `CORE/vhdl/mega65.vhd:681` checks only one buffer. A smaller `RAMSIZE` (512 kB is enough for 404 x 250 x 3 = 303 kB plus line padding) would put all three buffers into 1.5 MB, but `RAMSIZE` is computed from the OSM canvas (`G_VGA_DX * G_VGA_DY`), not from the core's picture, and the writes are wrapped with `RAMSIZE - 1` (1664). On R4 to R6 (SDRAM, ascal alone, 22-bit word addresses = 8 MB) three 2 MB buffers fit. **[code + inference]**
3. **Keep the controller in the HDMI clock domain** and change `htotal`/`vtotal` there (no synchronizer inside ascal). Change only the totals; leave the sync positions, `hdisp`/`vdisp` and the picture window alone.
4. **Triple mode boundary:** the input frame end (`i_vs` rising, as captured by the output clock) must not coincide with the output vsync end (`vsend`, `hsstart`) within plus or minus one output clock. Lowest-latency safe target: input frame end a few output lines before the output vsync ends.
5. **Direct mode target:** keep the gap between writer and reader positive at the critical end of the picture (top for 720p and 576p; bottom for NTSC 480p) by a few input lines (MiSTer: 4, flicker-free today: 7 to 14), and below one frame at the other end.
6. **Expect a re-acquisition after a core reset or a PAL/NTSC change;** during it direct mode tears and triple mode drops or repeats a frame.
7. **The HDMI audio clock regeneration value follows the mode's nominal clock** (`audio_pcm_cts <= hdmi_video_mode.CLK_KHZ`, `digital_pipeline.vhd:305`); a mode with a different pixel clock needs its own `CLK_KHZ`. (Outside ascal, noted because it travels with the totals.)

## 11. GHDL experiment

Bench `tb_ascal_lock` around a copy of our ascal (scratch folder of the research session, not in the repository). The copy differs from `M2M/vhdl/av_pipeline/ascal.vhd` only by four added debug output ports (the `E` and `S` conditions, `o_ibuf0`, `o_obuf0`) and two expressions rewritten with the modulo wrap the hardware performs anyway, because GHDL stops on the negative intermediate value at start-up (`o_pshift <= o_off(0) - 1` and `o_ihsizem <= o_ihsize + o_off(0) - 2` while `o_off(0)` or `o_ihsize` is still 0). Configuration as in our design except the sizes: `mode` 8 (triple, nearest), `INTER`/`HEADER`/`DOWNSCALE` false, `N_DW` 128, `N_BURST` 128, `OHRES` 2048, `FRAC` 4. Input 100 x 40 pixel periods (`i_ce` every second 10 ns clock), active 64 x 30, vsync on lines 36 and 37, red = x, green = y, blue = input frame number. Output 125 x 80 clocks of 8 ns (frame 80 µs, equal to the input), active 96 x 60, vsync lines 65 to 69. Avalon model: zero wait states, 8-beat bursts, read latency 12 clocks, separate 9.7 ns clock.

Results:

- **Equal periods, constant phase** (`S - E` = 1.712 µs): every output frame shows exactly one input frame, in order (frame numbers 1, 2, 3, ... with `bmin = bmax` in every frame), checksum of red and green identical in every frame. **[sim]**
- **`htotal` pseudo-random 124/125/126 per line and `vtotal` alternating 80/81 per frame** (changed at the falling edge of `o_hs` / `o_vs`, in the output clock domain): 96 x 60 pixels in every frame, the red/green checksum identical to the unmodulated run in every frame, one input frame per output frame, no mixed frame. **[sim]**
- **Slow drift through the triple-buffer boundary** (output clock 7.999 ns, so each output frame is 10 ns shorter than an input frame; `S - E` steps down by one or two output clocks per frame): while `E` came one output clock before `S` (`S - E` = 8 ns) or in the same clock (0 ns, the "simultaneous" branch), the frame just completed was shown in the next output frame. In the first frame in which `E` came one clock after `S`, the previous frame was shown again (input frame 20 twice); from then on every frame was shown once, one output frame later than before. Exactly one repetition, no skip, no other disturbance. **[sim]**
- RESULT_DIRECT_PLACEHOLDER
