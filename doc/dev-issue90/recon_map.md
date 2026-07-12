# C64MEGA65 — Physical Internal 1581 READ Path: Consolidated Recon / Design Input (issue #90)

Scope: add a **read-only** path so the MEGA65's real internal 3.5" DD floppy can back Commodore drive 8, feeding the WD1772 model (`fdc1772.v`) from a new 50 MHz MFM decoder instead of the virtual SD image. All refs are `file:line` in the current working tree. Register/hex tokens are kept in `inline code` to stay literal.

---

## 1. Clock & reset domains

### 1.1 The three clocks in play

| Clock | Frequency | Name at boundaries | Source |
|---|---|---|---|
| Physical MFM controller clock | **50 MHz** | `c64_clk_sd_i` (entity `main`, `main.vhd:131`) == `qnice_clk_i` (mapped `mega65.vhd:721`) == `qnice_clk` at top (`top_mega65-r3.vhd:219`) | `clk_m2m.vhd:79` `CLKOUT0_DIVIDE=>20`, VCO 1000 MHz → exactly 50 MHz; `QNICE_CLK_SPEED := 50_000_000` (`globals.vhd:55`) |
| Drive-logic / WD1772 command clock | ~31.528 MHz core clock, gated to ~16 MHz via `ce` | `clkcpu` inside fdc1772 = `clk` in `c1581_drv`/`c1581_multi` = `clk_main_i` (`main.vhd:25`, `CORE_CLK_SPEED_PAL := 31_527_778`, `globals.vhd:47`) | `clk` MMCM, `main_clk_o` |
| WD1772 8 MHz command-timer enable | ~8 MHz CE strobe | `clk8m_en` = `wd_ce` (`c1581_multi.sv:91`, mapped `c1581_drv.sv:237`) | divider in `c1581_multi.sv:77-93` |

**Decision: the physical controller runs on `c64_clk_sd_i` (50 MHz = QNICE clock).** It is already brought all the way into the drive subsystem (`main.vhd:1608` uses it as the drive `clk_sys`; `mega65.vhd:721` wires `c64_clk_sd_i => qnice_clk_i`). No new PLL/MMCM is required. Alternative (dedicated `clk.vhd` CLKOUT or `/2` off the 100 MHz `clk_i`) is cleaner in domain-isolation terms but spends MMCM budget — not recommended for the MVP.

### 1.2 What runs where inside fdc1772.v

- **`clkcpu` (~16 MHz drive clock)** owns: register file (`label` ~`fdc1772.v:1018`), IRQ/DRQ set/clear (`:203-235`), command FSM `label2` (`:373-709`), CPU/DRQ data pacing `label4` (`:884-969`), status mux (`:1001-1012`), FIFO **port B** (`:754-758`), the `floppy.v` mechanical model + `dclk_en` byte pacing.
- **`clk8m_en`/`wd_ce`** gates every ms timer in `label2` (`if (clk8m_en)` at `:410`) and data pacing.
- **`clk_sys` (QNICE 50 MHz)** owns: SD-transfer FSM `label3` (`:804-862`), FIFO **port A** (`:748-752`), and the ROM-BRAM write/readback ports in `c1581_multi.sv` (negedge `clk_sys`).

### 1.3 CDC boundaries (existing + new)

- **Existing, reuse the discipline:** clkcpu↔clk_sys handshake is toggle-synced via `iecdrv_sync` — request pulses `sd_card_read/sd_card_write` → `sd_rd_req_tgl/sd_wr_req_tgl` → synced to clk_sys (`fdc1772.v:783-802`); completion `sd_done_tgl` synced back to clkcpu (`:802`). The 512-byte FIFO is a dual-clock `fdc1772_dpram #(8,10)` (`:746-758`) — the canonical clk_sys↔clkcpu byte bridge.
- **New crossing required:** the physical decoder is on **50 MHz (`c64_clk_sd_i`)** while the WD command FSM is on **~16 MHz (`clkcpu`)** — a *non-integer-ratio async* crossing. Every request/result/status net must use `iecdrv_sync`/toggle handshakes; a bare level net will glitch/read-0. There is a documented in-repo Vivado hazard (forward-ref scalars in generate blocks synth undriven — memory `project_vivado_generate_forward_ref_nets`) — watch for it when threading through the `c1581_multi` generate loop.
- **`f_rdata_i` is fully asynchronous** (raw flux from the drive). It must go through a 2-FF metastability synchronizer into the 50 MHz domain before edge detection. Precedent: SRQ 2-FF sync at `main.vhd:1556-1562`. DD-MFM at ~250 kbit/s → transitions every ~2-4 µs; 20 ns (50 MHz) sampling is ample.

### 1.4 QNICE-domain reset — does one reach the physical controller?

**No, not today.** Entity `main` receives only `clk_main_i`, `reset_soft_i`, `reset_hard_i`, `c64_clk_sd_i` — there is **no** `main_osm_control_i` and **no** `c64_rst_sd_i` port. A QNICE-domain reset *does* exist one level up: `qnice_rst_i` on `MEGA65_Core` (`mega65.vhd:35`). **Add a new in-port `c64_rst_sd_i : in std_logic` to entity `main` and map it `=> qnice_rst_i` in `i_main`.** No MMCM `locked` signal is exported from `clk_m2m.vhd`/`clk.vhd` to the core (confirmed: `clk_m2m` emits no `locked`; `qnice_locked`/`audio_locked` are internal, consumed only for reset gen `:184/200/213/225`). Use de-assertion of `c64_rst_sd_i`/`qnice_rst` as the "clock valid" proxy; a genuine lock export would require touching `clk_m2m.vhd` + `framework.vhd` (M2M/core-independent — affects all cores).

---

## 2. Port-threading path (top → fdc1772)

New ABI to flow down the stack:
- **Physical outputs (drive control):** `step`, `dir`, `side`, `select`, `motor`, `density`.
- **Live physical state (up to the model):** `motor-at-speed/ready`, `index`, `track0`, `write-protect`, `disk-change`.
- **Read datapath:** request `{track, side, sector}` (or `sd_lba_comb`) down; result `{byte-stream, write-strobe, done}` up.
- **Mode select:** a single OSM bit (drive-8 physical vs virtual).

### 2.1 The chain

```
top_mega65-r{3,4,5,6}.vhd   (f_* board pins; today tied to '1' / dangling)
   └─ CORE : MEGA65_Core  (mega65.vhd) — ADD f_* ports; decode C_MENU_INTERNAL_1581
        └─ i_main : main   (main.vhd)  — ADD phys_1581_en_i, c64_rst_sd_i, f_* ; instantiate CORE/vhdl/physical_1581/*
             └─ iec_drive_inst : iec_drive.sv — ADD physical_mode; gate sd_rd/sd_wr; force 1581 engine active
                  └─ c1581_multi.sv (generate loop, drive idx 0 only) — thread phys ports
                       └─ c1581_drv.sv — re-source PA7/PB6/PA1; thread phys ports; drive motor/side/step
                            └─ fdc1772.v — mux read data source + mechanics; block writes
```

### 2.2 Per-file port additions

**`top_mega65-r{3,4,5,6}.vhd`** — pins already declared (`top_mega65-r3.vhd:170-185`; r6:191-205), all `std_logic`:
- Inputs (read): `f_rdata_i` (P1/F_RDATA1, `:176`), `f_index_i` (M2, `:173`), `f_track0_i` (N2, `:182`), `f_writeprotect_i` (P2, `:185`), `f_diskchanged_i` (R1, `:172`).
- Outputs (control): `f_motora_o` (M5, `:174`), `f_selecta_o` (N5, `:177`), `f_side1_o` (M1, `:179`), `f_stepdir_o` (P5, `:180`), `f_step_o` (M3, `:181`), `f_density_o` (P6, `:171`).
- Keep write-path outputs safe: `f_wdata_o` (`:183`), `f_wgate_o` (`:184`) stay `'1'`. `f_selectb_o`/`f_motorb_o` (`:175/178`) stay `'1'` (drive B, not used).
- **Remove** the matching lines from the static `<= '1'` block (`top_mega65-r3.vhd:464-473`) for every output the controller now drives; leave `f_wdata_o`/`f_wgate_o`/`f_selectb_o`/`f_motorb_o` tied `'1'`.
- Wire the 11 pins into the `CORE : MEGA65_Core` port map, in the "C64 specific ports" region (`top_mega65-r3.vhd:820-887`, next to IEC block `:824-835`). XDC pins are real: `MEGA65-R3.xdc:228-242` (`LVCMOS33`).

**`MEGA65_Core` (`mega65.vhd`)** — currently has **zero** `f_*` ports:
- Add the 11 `f_*` ports (mirror IEC region).
- Add `constant C_MENU_INTERNAL_1581 : natural := 3;` in the `C_MENU_*` block (`:347-422`) and decode `main_osm_control_i(C_MENU_INTERNAL_1581)` into a discrete signal (copy `iec_hardware_port_en_i => main_osm_control_i(C_MENU_IEC)` at `:729`, and `c64_exp_port_mode(0) <= main_osm_control_i(C_MENU_SIM_CRT)` at `:583`).
- Add `phys_1581_en_i` + `c64_rst_sd_i` + the `f_*` ports to the `i_main` port map (`:609-830`). Optionally instantiate `physical_1581` here on `qnice_clk` instead of in `main` — but the ABI mux to the drive lives in `main`, so instantiate in `main`.

**Entity `main` (`main.vhd`)** — add in-ports:
- `phys_1581_en_i : in std_logic` (mode select; map `=> main_osm_control_i(C_MENU_INTERNAL_1581)`).
- `c64_rst_sd_i : in std_logic` (map `=> qnice_rst_i`; 50 MHz reset).
- The 11 `f_*` ports (5 in, 6 out).
- Instantiate `physical_1581_inst : entity work.<controller>` on `c64_clk_sd_i`/`c64_rst_sd_i`.

**`iec_drive.sv`** (`module iec_drive #(PARPORT=0, DUALROM=1, DRIVES=G_VDNUM)`, `G_VDNUM=C_VDNUM=1` → `NDR=1, N=0`):
- Add `input [N:0] physical_mode` near `img_type` (`:24`), latched `posedge clk` like `dtype` (`:87`) — quasi-static.
- **Force engine selection:** 1581 reset gate `:168` `.reset(reset | ~dtype[1])` → `.reset(reset | ~(dtype[1] | physical_mode))`; 1541 gate `:116` `reset | dtype[1]` → `reset | dtype[1] | physical_mode` (only one engine owns the AND-wired IEC bus).
- **Gate sd_rd/sd_wr off:** in the `always_comb` `:105-111`, `sd_rd[i] = physical_mode[i] ? 1'b0 : (dtype[1][i] ? c1581_sd_rd[i] : c1541_sd_rd[i]);` and same for `sd_wr[i]` (`:108/109`). `sd_lba`/`sd_blk_cnt`/`sd_buff_din` can be left (harmless when rd/wr=0).
- Thread the physical read/state/control ports through to `c1581_multi`.

**`c1581_multi.sv`** — thread phys ports into module (`:11-58`) and the per-drive generate loop (`:186+`), gated to drive index 0 (internal). Other drives stay virtual.

**`c1581_drv.sv`** — re-source the CIA senses (see §3 polarity table): mux `wps_n` (`:82-87`), `disk_chng_n` (`:78,228-231`), `floppy_ready` (`fdc1772` out) from physical inputs when `physical_mode`. Drive real `f_motora_o`/`f_side1_o`/`f_step_o` from `motor_n`/`side`/`floppy_step`. Add phys ports to port list (`:10-57`).

**`fdc1772.v`** — mux data source + mechanics; block writes (see §3).

### 2.3 Where sd_rd/sd_wr must be gated off

**Primary gate:** `iec_drive.sv:108-109` (mask exported `sd_rd[i]/sd_wr[i]` to 0 when `physical_mode[i]`). This stops all image traffic to `vdrives` — vdrives only acts on `sd_rd|sd_wr`, so `sd_ack`/`sd_buff_wr` remaining wired is harmless. **Secondary safety:** in `fdc1772.v`, ensure `sd_card_read`/`sd_card_write` (`:578/628`) are never pulsed in physical mode so `label3` (`:804-862`) stays idle and `sd_lba` (`:817-826`) never asserts. Also confirm the `cache_dirty`/`prevent_reset` interlock (`main.vhd:617/1691`, vdrives) is not tripped — read-only means `cache_dirty` stays 0 (safe), but the physical drive must not appear "mounted+dirty".

---

## 3. fdc1772.v — WD1772 structure & physical-mode injection points

Params for the 1581 (`c1581_drv.sv:233`): `SECTOR_SIZE_CODE=2` (512 B), `SECTOR_BASE=1`, `EXT_MOTOR=1`, `FD_NUM=1`, `MODEL=2` (wd1772). `W=0`, `SECTOR_SIZE=512`.

### 3.1 Register / command / status / DRQ / IRQ

- **Registers** (`:995-998`): `FDC_REG_CMDSTATUS=0`, `TRACK=1`, `SECTOR=2`, `DATA=3`. CPU read mux `:1001-1012`; command latch / RESTORE preset / SEEK `step_to` `:1018-1099`.
- **Command classes** (`:990-993`): `cmd_type_1 = cmd[7]==0`; `cmd_type_2 = cmd[7:6]==2'b10`; `cmd_type_3 = cmd[7:5]==3'b111 || cmd[7:4]==4'b1100`; `cmd_type_4 = cmd[7:4]==4'b1101`.
- **Type-I** `seek_state` `:473-545` (restore/seek/step/step-in/step-out); step pulse+rate `:512-529`; **verify is a stubbed delay** (TODO `:534`); step-rate table `:346-352`.
- **Type-II** `:549-650`: read sector `cmd[7:5]==3'b100` (`:570`), write sector `cmd[7:5]==3'b101` (`:609`); RNF if `(sector-SECTOR_BASE) >= fd_spt` (`:571/610`).
- **Type-III** `:653-684`: read address `cmd[7:4]==4'b1100` (`:673`), read track `:661` (**fake**), write track `:667` (**fake**).
- **Type-IV** force-interrupt `:446-452`: `busy<=0`, optional immediate IRQ (`cmd[3]`) or IRQ-at-index.
- **IRQ/DRQ**: `irq` set by `irq_set` (`:219-222`), `drq` by `drq_set` (`:232-235`). Both are **unconnected** at `c1581_drv` — polled via status/data regs. Data paced by `fd_dclk_en` (`:930`): each strobe decrements `data_transfer_cnt`, raises `drq_set` (`:936`), copies `fifo_q → data_out` + `fifo_cpuptr++` (`:951-954`); `data_lost` (status b2) if `drq` still high (`:933-934`); `data_transfer_done` on last byte (`:965-966`).
- **Status word** (`:971-979`), MODEL=2: b7=`motor_on`, b6=write-protect (`fd_writeprot` when type-1/write), b5=`motor_spin_up_done`(type1)/0, b4=`RNF`, **b3=CRC error HARDWIRED `1'b0` (`:976`)**, b2=`fd_track0`(type1)/`data_lost`, b1=`~fd_index`(type1)/`drq`, b0=`busy`.

### 3.2 Virtual mechanics (what physical mode displaces)

`floppy.v` instance `:263-297`, demuxed at `:303-316`: `fd_index`, `fd_ready`, `fd_track[6:0]`, `fd_sector[4:0]`, `fd_sector_hdr`, `fd_dclk_en`, `fd_present`, `fd_writeprot=img_wp[fdn]` (`:311`), `fd_doubleside`, `fd_spt`. `floppy_ready = fd_ready && fd_present` (`:316`). Read-sector waits for the *virtual* rotational position: `if(fd_ready && fd_sector_hdr && (fd_sector==sector)) data_transfer_start<=1` (`:590`). Read-Address reply bytes synthesized in `label4` `:938-947` from `fd_track/fd_sector/floppy_side/SECTOR_SIZE_CODE` + CRC (`crcval` seed `16'hB230` `:914`).

### 3.3 Precise injection points for a physical read branch

Add `input phys_mode` (threaded per §2). Two candidate seams:

- **Option A — sector-result ABI (recommended; matches "request/result/read-byte" wording).** Keep the WD command FSM + FIFO untouched; the physical controller stands in for the `sd_*` path:
  1. fdc1772 hands `{fd_track, floppy_side, sector}` (or `sd_lba_comb`, `:85-96`) as the **request** in place of `sd_card_read`/`label3`.
  2. The controller MFM-decodes that sector and **results** 512 bytes into the FIFO **port A** (`address_a/data_a/wren_a`, `:749-752`) + a `done` toggle mirroring `sd_ack`/`sd_done_tgl`. The existing `fifo_q` read path (`:951-954`) is unchanged.
  3. Mechanical status (`fd_ready/fd_index/fd_sector_hdr/fd_sector/fd_track/fd_dclk_en`) still needs a physical source — either keep `floppy.v` as a *timing-only* model paced by the real index pulse, or feed these from the controller (Option B).
- **Option B — replace the demux + FIFO source.** Mux the demux nets `:303-316` to controller-sourced `fd_index/fd_ready/fd_track/fd_sector/fd_sector_hdr/fd_dclk_en` and either fill FIFO port A from the physical decoder or bypass the FIFO by muxing `data_out <= phys_byte` at `:951-953`. More faithful to "decode real DD-MFM"; touches more lines.

Either way, the `data_transfer_start` trigger at `:590` already fires on `fd_sector_hdr && fd_sector==sector`, so if the physical `fd_sector_hdr`/`fd_sector` reflect the real ID field, DRQ pacing "just works" off `fd_dclk_en`.

New fdc1772 ports to add: `phys_mode` (in); request-side `{phys_track/phys_side/phys_sector}` or `phys_lba` (out); result-side `{phys_data[7:0], phys_wr, phys_done}` (in); mechanical status `{phys_ready, phys_index, phys_wp, phys_change, phys_track0}` (in); control `{phys_step, phys_dir, phys_side_o, phys_motor}` (out — note step direction, see §7).

Other structure edits:
- **Status CRC bit** `:976` `1'b0` → real `phys_crc_err` in physical mode.
- **RNF** (`:367`): source from controller "ID not found after N index pulses" instead of "sector ≥ spt".
- **Read Address** `:938-947`: drive the 6 reply bytes from the real ID field + real/recomputed CRC.
- **Read Track** `:661` (fake): a genuine extension point if raw-track streaming is ever wanted (out of MVP scope).
- **Writes blocked:** never route `cmd[7:5]==3'b101` (write sector `:609-648`), write-track (`:667`), or `sd_wr` to the physical drive. Force write-protect (`fd_writeprot=1` / PB6=read-only) so 1581 DOS never attempts a write.

---

## 4. Menu / OSM delta

### 4.1 `config.vhd` edits (all confirmed line refs)

1. **New group-id constant** (`:588-617` block; ids 1..30 contiguous, 31 free): `constant OPTM_G_INT1581 : integer := 31;` (`OPTM_G_VICII_MODEL := 30` is current highest; group id lives in bits 7..0, flags start at bit 8, ceiling `2**OPTM_GTC-1` fine).
2. **`OPTM_ITEMS` text** — insert between `:414` (`" 8:%s\n"`, flat 2) and `:415` (`" PRG:%s\n"`, flat 3): a line ≤ ~23 printable chars (`OPTM_DX=25` limit), e.g. `" Use internal 1581\n" &`. New line = **flat index 3**; `" PRG:%s\n"` shifts to flat 4.
3. **`OPTM_GROUPS`** — insert between `:628` (drive-8 `OPTM_G_MOUNT_8+...`, idx 2) and `:629` (`OPTM_G_LOAD_PRG+...`, idx 3): `OPTM_G_INT1581 + OPTM_G_SINGLESEL,` (add `+ OPTM_G_STDSEL` for default-On; precedent `OPTM_G_IEC + OPTM_G_SINGLESEL` `:734`, `OPTM_G_REU + OPTM_G_SINGLESEL` `:636`). **Must NOT carry `OPTM_G_MOUNT_DRV`** (bit 11) — that would make the Shell count it as another drive.
4. **`OPTM_SIZE`** `:394` `159` → **160** (must equal count of `\n` lines == `OPTM_GROUPS` entries).
5. **`OPTM_DY`** `:404` `27` → **28** (a main-menu visible line was added).
6. **`CORE_VERSION`** `:71` — bump (recommended): `CFG_FILE = "/c64/c64mega65-" & CORE_VERSION` (`:240`) gets a fresh filename, sidestepping the now-incompatible saved-settings bitmap (`SAVE_SETTINGS=true` `:290`; every saved bit ≥ flat 3 shifts). Regenerate with `M2M/tools/make_config.sh c64mega65-<CORE_VERSION> auto` at the new `OPTM_SIZE`.

`OPTM_DX=25` (`:403`). The address-decode process tail (`:905-939`) is index-driven/generic — **no change**; adding one array element is served automatically. WHS help array unchanged.

### 4.2 `mega65.vhd` C_MENU_* decode

- Add `constant C_MENU_INTERNAL_1581 : natural := 3;` in the `C_MENU_*` block (`:347-422`).
- **Flat-index shift (blast radius):** `C_MENU_*` are *flat menu indices*, not group ids (confirmed: `C_MENU_EXP_PORT_HW=7` == `" Use hardware slot\n"` flat 7). Inserting at flat 3 means **every existing `C_MENU_*` ≥ 3 must increment +1**: `C_MENU_EXP_PORT_HW 7→8`, `SIM_CRT 8→9`, `SIM_REU 10→11`, … `VICII_OLDHMOS 150→151`, plus the two subtype ranges `C_MENU_VOLUME (123 downto 113)→(124 downto 114)` (`:415`) and `C_MENU_OSM_SCALING (141 downto 133)→(142 downto 134)` (`:418`).
- Decode `main_osm_control_i(C_MENU_INTERNAL_1581)` → discrete signal → `i_main.phys_1581_en_i`.

### 4.3 QNICE asm mirror (`CORE/m2m-rom/osm_const.asm`)

- `C64_OSM_*` (`:17-53`) are **flat indices** → all ≥ 3 shift **+1** in lockstep with `C_MENU_*`.
- `C64_OPTM_G_*` (`:72-101`) are **group ids** → unchanged; add `C64_OPTM_G_INT1581 .EQU 31`.
- Group-id compares in `m2m-rom.asm` (`FILTER_FILES`, `SUBMENU_SUMMARY`) are safe; any flat-index math must account for +1.

### 4.4 Verification gate

Run `python3 M2M/rom/tests/menu_test.py verify` after edits — it parses **both** `config.vhd` and `mega65.vhd` and cross-checks OSM consistency (flagged at `mega65.vhd:344-345`, `config.vhd:402`). It catches `OPTM_SIZE`/`OPTM_DY` miscounts and `C_MENU_*` vs `OPTM_ITEMS` flat-index drift.

---

## 5. QNICE diag device (read-only `C_DEV_C64_PHYS1581 = 0x0108`)

Optional — only if the controller must expose decoded state/bytes to QNICE for debugging. `x"0108"` is confirmed free (`globals.vhd:85-92`; highest used `C_DEV_C64_KERNAL_C1581 x"0107"`; `0x01xx` is this core's block).

**Pattern to copy** (read-only BRAM, no wait-state — mirror `C_DEV_C64_RAM`):

1. **globals.vhd** `:93` — add `constant C_DEV_C64_PHYS1581 : std_logic_vector(15 downto 0) := x"0108";`.
2. **mega65.vhd device decode** (`core_specific_devices`, `process(all)` `:879`, branches `:903-967`) — add `when C_DEV_C64_PHYS1581 =>` mirroring the `C_DEV_C64_RAM` branch (`:905-909`): drive `*_ce`/`*_addr` into the diag BRAM's QNICE port, return `qnice_dev_data_o <= x"00" & <byte>`. **Add the branch's default assignments to the avoid-latches block `:882-901`** (the `process(all)` auto-senses new signals but you still need defaults).
3. **Instantiate the diag BRAM** copying `c64_ram : entity work.dualport_2clk_ram` (`:1040-1064`): `ADDR_WIDTH/DATA_WIDTH` to taste, `FALLING_A=>false` (side A = 50 MHz physical decoder writes decoded bytes), `FALLING_B=>true`, `clock_b => qnice_clk_i` (side B read-only for QNICE). **No `qnice_dev_wait_o`** needed for BRAM (the `C_DEV_C64_RAM` branch drives no wait; only HyperRAM-backed devices `C_DEV_C64_MOUNT`/`C_DEV_C64_CRT` `:919-941` use it).

If the controller is purely a main-clock↔50 MHz RTL block feeding fdc1772, **no `C_DEV_*` is required** and globals.vhd/mega65.vhd device decode stay untouched. Decide before claiming `x"0108"`.

---

## 6. R3 pin plumbing & capability

- **Pins are real on R3, currently dead.** `top_mega65-r3.vhd:170-185` declares all 16 `f_*` pins; outputs are tied `'1'` at `:464-473` (Shugart idle, active-low deasserted); the 5 inputs (`f_diskchanged_i/f_index_i/f_rdata_i/f_track0_i/f_writeprotect_i`) dangle. XDC: `MEGA65-R3.xdc:228-242` (`LVCMOS33`). None reach `MEGA65_Core` today (grep: `f_*` appear only in the four `top_mega65-r*.vhd` entity/tie-off blocks; `MEGA65_Core` has zero `f_*` ports).
- **To wire the read path (per §2.2):** delete the driven outputs from the `:464-473` block (keep `f_wdata_o/f_wgate_o/f_selectb_o/f_motorb_o <= '1'`), add the 11 `f_*` ports to `MEGA65_Core`, and wire them in the `CORE` instantiation's "C64 specific ports" region (`:820-887`).
- **Capability gating (R3-only is a scoping decision, not a hardware limit — r4/r5/r6 have the same pins + XDC):** `G_BOARD : string` already discriminates (`mega65.vhd:26`, set `"MEGA65_R3"` at `top_mega65-r3.vhd:672`). Gate the feature with `if G_BOARD = "MEGA65_R3" generate` inside `mega65.vhd`, **or** add an explicit `G_INTERNAL_1581 : boolean` generic that only the R3 top sets `true` (cleaner; lets other boards opt in later). The OSM item should also be hidden/disabled on non-R3 if it is compiled per-board.
- **Available clocks at top level:** `clk_i` 100 MHz raw (`:107/762`), `qnice_clk` **50 MHz** (already routed into the core at `:686`), `main_clk` ~31.53 MHz (core out; note stale "54 MHz" comment `:678`), `hr_clk` 100 MHz, `audio_clk` 12.288 MHz. **The 50 MHz `qnice_clk` is already inside the core** — the controller needs no new top-level clock net.
- **PLL-lock:** **none exported** (`clk_m2m.vhd` emits no `locked`; `framework.vhd` drops `sr_*` as `open`). Use `qnice_rst` de-assertion as the ready-proxy, or add a `locked_o` chain through `clk_m2m.vhd` + `framework.vhd` (M2M-wide change) if a true lock gate is needed.

---

## 7. Open risks / unknowns to resolve during implementation

1. **Step direction not exposed by the WD model.** `floppy_step` (`fdc1772.v:357 = step_in|step_out`) is a single OR'd pulse; direction lives only in `label2` (`:490 step_dir <= (step_to<track)`). Physical head needs `dir` — add a `step_dir`/`step_in`/`step_out` output to fdc1772, and provide a real **track-0 sensor** (`f_track0_i`) to close the RESTORE loop (WD `fd_track0` at `:364`).
2. **Single-phase vs two-phase read handshake.** Virtual read is "fill FIFO from SD, *then* wait for header" (`:578-590`). A real drive has no pre-fill — the header passes once per rotation. The sequencing must collapse to "wait header, then stream on `fd_dclk_en`", or the header is missed while idling on a non-existent SD fill.
3. **ID-field timing granularity.** The WD samples `fd_sector==sector` only while `fd_sector_hdr` is high (`:585-590`). The physical decoder must present a stable decoded ID number for enough `clkcpu` cycles during the real ID window.
4. **`floppy_ready`/spin-up coupling.** PA1 ready and status b7/b5 both derive from `floppy_ready`/`motor_spin_up_done`. `EXT_MOTOR=1` means motor = `floppy_motor = ~motor_n` (`fdc1772.v:261`, `c1581_drv.sv:243/133`). Physical `fd_ready` must gate on the *real* spin-up (index seen), not `floppy.v`'s simulated rate; a mismatch hangs the 1581 DOS ready-wait loop.
5. **`img_mounted`-driven latches never fire in physical mode.** `wps_n` (`c1581_drv.sv:82-87`), `disk_chng_n` (`:78,228-231`), `fd_present` (from `|img_size`, `fdc1772.v:187`) all key off a mount event that won't happen. Without re-sourcing, the disk appears "permanently changed" / "write-protected" / "not present" and Type-I/II bail out with RNF (`:461-470,550-559`). Must synthesize `fd_present=1` from real disk-change and re-source PA7/PB6/PA1 from physical sensors.
6. **1581 engine held in reset without a mounted D81** (`iec_drive.sv:168` needs `dtype[1]=1`, set only on `img_mounted[i] && img_size` at `:87`). The single biggest correctness risk — `physical_mode` must force the engine out of reset (§2.2) and present `img_type="10"` (or rely solely on the physical-forces-1581 gate).
7. **Non-integer async CDC 50 MHz → ~16 MHz.** All request/result/status nets need `iecdrv_sync`/toggle handshakes; a bare net glitches. Beware the generate-block undriven-net Vivado hazard (memory `project_vivado_generate_forward_ref_nets`).
8. **Write path must stay inert.** READ-only MVP: force `sd_wr=0` (`iec_drive.sv:109`), present the physical disk as write-protected (PB6/`img_wp`), keep `f_wdata_o/f_wgate_o` tied `'1'`, and never pulse `sd_card_write`. Verify DOS does not silently write the RAM image while the user believes it uses the real disk.
9. **Head/side & double-sided.** D81 is double-sided; `floppy_side` feeds Read Address (`:942`) and `sd_lba` (`:89-93`). The physical decoder must expose the real side and map head consistently to the demuxed nets.
10. **Diag-device decision.** Claiming `C_DEV_C64_PHYS1581 = 0x0108` is only warranted if QNICE must observe the controller; otherwise leave globals/mega65 device decode untouched. Decide early to avoid churn.
11. **NTSC clock.** `CORE_CLK_SPEED_NTSC` (`globals.vhd:48`) is an untuned `@TODO`. If any physical timing is derived from the main clock in NTSC it inherits that inaccuracy; the 50 MHz QNICE clock itself is exact.
12. **`OPTM_DY` recount.** 27→28 was counted by hand from `OPTM_GROUPS`; treat `menu_test.py verify` as the authority (off-by-one truncates/over-sizes the menu window).
