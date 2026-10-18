# WD1772 write path and the physical-1581 write ABI — recon for the write milestone

Repo: `/Users/mirko/Documents/Privat/GNR/dev/MEGA65/C64MEGA65`, branch `mh_dev_drives` (nothing modified). All line numbers are from the current working tree. `fdc` = `CORE/C64_MiSTerMEGA65/rtl/iec_drive/fdc1772.v`, `ctl` = `CORE/vhdl/physical_1581/physical_1581_controller.vhd`.

## 0. What phys-mode writes do today (the short answer)

- **Write Sector (`cmd[7:5]=101`) in phys mode is a WD-side fake-finish, not a write-protect refusal by the mechanism.** `fdc:980-984`: on the first `clk8m_en` execute tick after acceptance the command ends with `busy <= 1'b0; irq_set <= 1'b1;` — no `phys_rd_req_tgl`, no `data_transfer_start`, no `sd_card_write`, no DRQ. Nothing reaches the controller or the media.
- **The status register then shows bit 6 (WRITE PROTECT) forced to 1** regardless of the real tab: `fdc:1710-1713`
  `phys_mode ? ( ((cmd[7:5] == 3'b101) || (cmd[7:4] == 4'b1111)) ? 1'b1 : (cmd_type_1 ? phys_wprot_c : 1'b0) ) : (... && fd_writeprot)`. So the DOS job epilogue sees a "write protected" completion (expected to surface as DOS error 26, WRITE PROTECT ON — I did not verify entry 8 of the ROM's `\$CD5A` table; the docs only quote its first entries).
- **`img_wp` / `fd_writeprot` are NOT forced in phys mode**: `fd_writeprot = fd_any ? img_wp[fdn] : 1'b1` (`fdc:595`) is only consumed by the image-mode status expression (`fdc:1713`). In phys mode the Type-I WP bit comes from the real tab via `phys_wprot_c` (`fdc:208`), and the CIA PB6 /WPRT senses the real tab too (`c1581_drv.sv:215`). A writable physical disk therefore passes the DOS pre-check and the DOS *does* issue the WD write command, which then fake-finishes.
- **Write Track (`1111`) and Read Track (`1110`) in phys mode** take the same immediate exit: `fdc:1122-1124` (`else` branch of the Type-III phys block). Status bit 6 is forced for `1111` as well. `RDOP_READ_TRACK = "011"` exists in the package (`physical_1581_pkg.vhd:197`) but is never issued.
- **Hazard worth flagging:** the phys fake-finish releases BUSY after one `clk8m_en` period (~125 ns, see 1.5). The round-11 analysis (`fdc:262-277`) showed the 1581 ROM command writer at `\$CBF4` spins in "wait busy-SET" with ~3.5 us polls and hangs when BUSY is that short; it was fixed for Type I only (`PHYS_T1_MIN_TICKS`, `fdc:278-279`, gate at `fdc:945`). If the ROM's write jobs use the same writer, a phys-mode write to a *writable* disk could wedge the DOS today. Untested on hardware (the read milestone never exercised writes). Moving writes onto the controller done handshake (HANDOVER §8.3, `doc/dev-fdd/HANDOVER.md:417-419`) removes this class structurally.
- **Pins:** `f_wgate_o`/`f_wdata_o` never enter `MEGA65_Core`; they are tied `'1'` in all four board tops (exact lines in §3.3). XDC already constrains them (N4/N3, LVCMOS33), so no constraint change is needed.

## 1. fdc1772.v — map

### 1.1 Blocks / labels

| Block | Lines | Clock | Role |
| --- | --- | --- | --- |
| module header, parameters | `fdc:32-41` | — | `CLK_EN=8000` kHz, `SECTOR_SIZE_CODE` (1581: 2 = 512 B), `SECTOR_BASE` (1581: 1), `EXT_MOTOR` (1581: 1), `MODEL=2` |
| ports | `fdc:42-140` | — | phys ABI at 82-140 (table in 1.6) |
| forward decls + `#248` write regs | `fdc:144-189` | — | `data_transfer_abort`, `wr_first_wait`, `wr_first_grace`, `WR_FIRST_GRACE=27` (`fdc:179-186`) |
| phys CDC + engine state | `fdc:191-336` | clkcpu | `iecdrv_sync` instances 205-220; `phys_rd_done_c_d1/_d2` 230-236; `PHYS_PACE_TICKS` 259; `PHYS_T1_MIN_TICKS` 278; `phys_cpu_rd_data_open` 302; `phys_present_now` 314-317; `phys_active` etc. 323-326; `initial` 332-343 |
| `sd_lba_comb` | `fdc:352-363` | comb | size code 2: `((fd_spt*track) << fd_doubleside) + (floppy_side ? 0 : fd_spt) + sector - 1` (`fdc:358`) |
| image geometry decode | `fdc:365-445` | comb | D81 (819200 B) -> `image_doubleside=1`, `image_spt=10` |
| `label0` | `fdc:447-463` | clkcpu | latch per-drive geometry on `img_mounted` rising edge |
| IRQ/DRQ | `fdc:469-510` | clkcpu | `drq_clr = !floppy_reset \| cpu_rw_data \| phys_cmd_clear \| (!phys_mode && cmd_rx && !cmd_type_4)` (`fdc:504-505`) |
| `label1` + `floppy` instances | `fdc:525-568` | comb | drive select demux, image mechanics model |
| floppy demux | `fdc:574-606` | comb | `fd_hdr_rise` 593, `fd_writeprot` 595, `floppy_ready` 601, `fd_index_eff` 606 |
| `label2` | `fdc:663-1343` | clkcpu @ `clk8m_en` | THE command FSM (details below) |
| FIFO `fdc1772_dpram #(8,10)` | `fdc:1356-1369` | A: clk_sys, B: clkcpu | 1 kB; port A = vdrives side (`q_a -> sd_din`), port B = drive CPU side (`wren_b = data_in_strobe`) |
| `label_sdreq` | `fdc:1396-1403` | clkcpu | 1-cycle `sd_card_read/write` -> `sd_rd_req_tgl/sd_wr_req_tgl` |
| `label3` | `fdc:1413-1470` | clk_sys | SD request FSM: `sd_rd/sd_wr/sd_lba`, `sd_done_tgl` back |
| `crc()` function | `fdc:1475-1491` | — | CCITT, used for Read Address reply |
| `label4` | `fdc:1493-1703` | clkcpu | data register / DRQ pacing / phys presentation / image write FIFO fill |
| status word | `fdc:1710-1728` | comb | bit map below |
| `cmd_type_*` | `fdc:1733-1736` | comb | type 1 `cmd[7]=0`; 2 `10x`; 3 `111x` or `1100`; 4 `1101` |
| CPU register read/write | `fdc:1739-1853` | clkcpu | busy-ignore of non-FI commands in phys mode `fdc:1783-1785`; `cmd <= cpu_din; cmd_rx_i <= 1` `fdc:1786-1787`; `phys_set_sector` 1847 |

### 1.2 Image-mode Write Sector, step by step

1. **Command write** `fdc:1786-1787` (`cmd <= cpu_din; cmd_rx_i <= 1'b1`), `cmd_rx` one clkcpu later (`fdc:1770`). The write-sector case at `fdc:1811` is empty (no register side effects).
2. **Acceptance** (`label2`, next `clk8m_en`): `fdc:747-748` `busy <= 1'b1`, `data_transfer_state <= 0`; `fdc:760-766` `RNF <= 0; motor_on <= 1;` and `if (!motor_on && !cmd[3]) motor_spin_up_sequence <= 6` (6 index pulses of the image model). Image mode clears DRQ on acceptance through `drq_clr` (`fdc:505`); `label4` resets `fifo_cpuptr`, `data_transfer_cnt`, `data_in_valid`, `wr_first_wait` on `cmd_rx` (`fdc:1515-1521`) and clears sticky `data_lost` (`fdc:1695`).
3. **Execute gate** `fdc:805`: `busy && motor_spin_up_done && !step_busy && !delaying`.
4. **Type-II image branch** `fdc:986-1097`: `!fd_present` -> RNF after 6 ms (987-996); `sector_not_found` -> RNF (997-1000); e-flag (`cmd[2]`) -> one 15 ms `delay_cnt` (1001-1004).
   **Write Sector** `fdc:1046-1095`:
   - `fdc:1047-1050`: `(sector - SECTOR_BASE) >= fd_spt` -> `sector_not_found`, `delay_cnt = 1000 ms` (RNF after "5 rotations").
   - `fdc:1051` everything below is gated on `sd_io_idle` (CDC-safe replacement for the old `sd_state == SD_IDLE`, see `fdc:683-690`).
   - state `2'b00` (`fdc:1053-1060`): pre-read only for `SECTOR_SIZE_CODE < 2` (not the 1581); -> `2'b10`.
   - state `2'b10` (`fdc:1061-1079`): `if (fifo_cpuptr == 0 && fd_ready && fd_sector_hdr && (fd_sector == sector)) data_transfer_start <= 1'b1;` (level start on the header, `fdc:1063`; the `#248` comment at `fdc:587-592` explains why writes keep the level start while reads use `fd_hdr_rise`). Then `if (data_transfer_abort) {state<=00; busy<=0; irq_set<=1}` (`fdc:1069-1073`, checked BEFORE done so both can never act in one tick) `else if (data_transfer_done) {sd_card_write <= 1; sd_io_idle <= 0; state <= 11}` (`fdc:1074-1078`).
   - state `2'b11` (`fdc:1081-1090`): reached only after `sd_io_idle` is set again by `sd_done_tgl` (i.e. after vdrives acked the write-back): `cmd[4]` -> `sector_inc_strobe` (multi-sector, loops to `00`), else `busy <= 0; irq_set <= 1`. **BUSY therefore covers the SD write-back.**
5. **`label4` DRQ pacing** (`fdc:1595-1690`):
   - on the `data_transfer_start` rising edge, write sector (`fdc:1622-1630`): `drq_set <= !data_in_valid;` then image mode: `data_transfer_cnt <= 0; wr_first_wait <= 1; wr_first_grace <= WR_FIRST_GRACE (27)`. (phys mode would instead load `SECTOR_SIZE+1` — dead in practice, see 1.4.)
   - every `fd_dclk_en` (image byte clock from `floppy.v`): first-byte grace `fdc:1639-1651`: if `data_in_valid` -> `data_transfer_cnt <= SECTOR_SIZE + 1` (data field starts next byte clock); else if `wr_first_grace == 0` -> `data_lost <= 1; data_transfer_abort <= 1` (sticky LOST DATA, nothing written); else decrement. 27 = header start (6 byte-times in `floppy.v`) + 22 byte-times gap -> abort on the 28th clock (`fdc:182-186`).
   - transfer (`fdc:1652-1687`): per byte clock while `cnt != 1`: `if (drq) data_lost <= 1` (CPU late -> sticky LOST DATA but the transfer continues); `drq_set` unless it is the last byte (`cnt == 2` for writes, `fdc:1656`); write: `data_in_strobe <= 1; data_in_valid <= 0` (`fdc:1676-1679`) which writes `data_in` into FIFO port B at `fifo_cpuptr` and advances the pointer next cycle (`fdc:1634-1635`); `cnt == 1` -> `data_transfer_done` (`fdc:1685-1686`).
   - `data_out <= data_in` readback mirror for image mode, `cpu_din` for phys (`fdc:1510`).
6. **SD write-back** `label3` (`fdc:1413-1470`): `sd_wr_req_s` edge -> `sd_wr[fdn] <= 1; sd_lba <= sd_lba_comb; sd_state <= SD_WRITE` (`fdc:1430-1434`); vdrives reads the FIFO through port A (`q_a -> sd_din`, `fdc:1361`); on `sd_ack` falling edge `sd_done_tgl` toggles (`fdc:1450-1461`); reset clause `fdc:1464-1469`. `iec_drive.sv:184` shifts the 1581 LBA (`c1581_sd_lba << 1`, 512-byte sectors on 256-byte vdrives blocks) and masks `sd_wr` to 0 in phys mode (`iec_drive.sv:189`).
7. **Status after a write** (`fdc:1710-1728`): b7 motor, b6 `fd_writeprot` (write cmds + Type I only), b5 0, b4 RNF, b3 0 (image mode has no CRC), b2 `data_lost`, b1 DRQ, b0 busy. Image WP = `img_wp = ~wps_n` (`c1581_drv.sv:336`), `wps_n` latched at mount from `~img_readonly` (`c1581_drv.sv:137-142`).

### 1.3 Image-mode Write Track — fake success

`fdc:1140-1144`:
```verilog
// write track TODO: fake
if(cmd[7:4] == 4'b1111) begin
    busy <= 1'b0;
    irq_set <= 1'b1; // emit irq when command done
end
```
- Reached through the Type-III image branch `fdc:1127-1157` (`!fd_present` -> immediate RNF, `fdc:1128-1133`).
- BUSY: set at acceptance (`fdc:748`), cleared on the first execute tick, i.e. **one `clk8m_en` period** (~125 ns) if the motor is already on; if the motor was off and h=0 it first waits `motor_spin_up_sequence = 6` image index pulses (1.2 s, `fdc:766` / `fdc:1316-1317`).
- **No DRQ is ever raised** (`label4` has no `1111` case at `fdc:1595-1631`), the data register is never sampled, **F5/F6/F7 are not interpreted at all**, nothing goes to the FIFO or to `sd_wr`. Status: b6 = `fd_writeprot`, b2 = 0, b1 = 0.
- Read Track (`1110`) is the same fake at `fdc:1135-1138`.

### 1.4 PHYS mode — Type II / III branches

```verilog
// fdc:955-984 (Type II phys)
if(cmd_type_2 && phys_mode) begin
    if (cmd[7:5] == 3'b100) begin                 // read sector
        if (!phys_rd_pending && !phys_done_latched && !phys_reissue) begin
            phys_rd_op <= 3'b000; phys_rd_track <= track; phys_rd_side <= floppy_side;
            phys_rd_sector <= sector; phys_rd_seq <= phys_rd_seq + 2'd1;
            phys_rd_req_tgl <= ~phys_rd_req_tgl; phys_rd_pending <= 1'b1;
            phys_reading <= 1'b1; phys_rd_start <= 1'b1;
        end
    end else if (cmd[7:5] == 3'b101) begin
        // write sector -> blocked; complete write-protected
        busy    <= 1'b0;
        irq_set <= 1'b1;
    end
end else
```
```verilog
// fdc:1100-1125 (Type III phys): Read Address issues RDOP_READ_ADDRESS (1108-1120)
end else begin
    // read track / write track: not physically supported -> finish
    busy    <= 1'b0;
    irq_set <= 1'b1;
end
```
- Phys mode skips the spin-up gate (`fdc:805`: `phys_mode ? 1'b1 : motor_spin_up_done`) and has no e-flag settle delay (the controller owns `head_settled`).
- On acceptance in phys mode: `phys_cmd_clear` (clears DRQ and `phys_lost_l`), latched result flags cleared (`fdc:772-776`); Force Interrupt toggles `phys_rd_cancel_tgl` and clears the engine (`fdc:789-797`).
- The `label4` phys write remnant `if (phys_mode) data_transfer_cnt <= SECTOR_SIZE + 1'd1;` (`fdc:1624`) only runs on a `data_transfer_start` edge, which no phys branch ever raises -> dead in practice. `fd_dclk_en` comes from the image `floppy` model which has no image in phys mode.
- Secondary safety already in place: `sd_rd/sd_wr` masked at `iec_drive.sv:188-189`, so even a stray `sd_card_write` could not reach vdrives.

### 1.5 PHYS_PACE_TICKS = 252 and the clock behind it

`fdc:254-259`: "One DD MFM byte-time is 32 us = 252 clk8m_en ticks (~7.88 MHz)". The actual enable chain: `main.vhd:2450-2468` is a fractional divider producing exactly 16 000 000 `iec_drive_ce` pulses per second from `clk_main_speed_i` (31.527778 MHz; the comment there says it keeps the drive at its nominal rate even when flicker-free slows the core); `iec_drive.sv` passes it as `ce`; `c1581_multi.sv:135-152` derives `wd_ce <= ena && !div[0]` = every second `ce` = **8.000 MHz nominal**, and `c1581_drv.sv:320` feeds it as `clk8m_en`. So 252 ticks = 31.5 us at 8.0 MHz (the "7.88 MHz" in the comment would be clk_main/4; at that rate 252 ticks = 31.98 us). Either reading is "one DD byte-time" (250 kbit/s -> 32 us) within the +-3% drive-speed tolerance; the point of 252 is that presentation is paced by disk time, never by consumption. Note `CLK_EN = 8000` kHz (`fdc:33`) is used for all ms timers (`fdc:636-645`).

**For the write milestone:** the WD-side pacer may reuse `clk8m_en` for DRQ cadence (<= byte pace is all the ROM needs), but the actual WDATA flux must be generated at exactly 2 us half-cells by the 50 MHz controller (`C_HALF_CELL_CYC = 100`, `physical_1581_pkg.vhd:37`), never from `clk8m_en`.

### 1.6 phys_* ABI (fdc:82-140) and the read handshake

| Direction | Port | Semantics |
| --- | --- | --- |
| in | `phys_mode` | 1 = this drive backed by the mechanism; everything else gated on it |
| out | `phys_active` | `phys_mode & floppy_reset` (`fdc:323`) -> controller `en` |
| out | `phys_cia_motor_on`, `phys_cia_side` | `floppy_motor` (= ~PA2), `floppy_side` (= ~PA0) (`fdc:324-325`) |
| out (reg) | `phys_step_req_tgl`, `phys_step_outward` | one Type-I step per toggle (`fdc:876-889`); dir latched first |
| out (reg) | `phys_rd_req_tgl`, `phys_rd_op[2:0]`, `phys_rd_track/side/sector`, `phys_rd_seq[1:0]` | read op request; params quasi-static before the toggle; seq bumped for EVERY issued op incl. multi-sector reissues (`fdc:1281-1292`) |
| out (reg) | `phys_rd_cancel_tgl` | Force Interrupt abort (`fdc:790`) |
| out | `phys_byte_ovf` | tied 0 (`fdc:326`); the real FIFO full flag goes to the controller at `main.vhd:2268` |
| in | `phys_step_ack_tgl` | one step mechanically complete (after recovery) |
| in | `phys_rd_done_tgl`, `phys_rd_done_seq[1:0]`, `phys_rd_result[4:0]`, `phys_rd_crc_err`, `phys_rd_rnf`, `phys_rd_deleted`, `phys_rd_c/h/r/n` | op completion; flags written in the SAME 50 MHz cycle as the toggle; consumed two clkcpu after the synced edge (`fdc:222-236`) |
| out (reg) / in | `phys_byte_rd_en` / `phys_byte_data[7:0]`, `phys_byte_empty` | FWFT FIFO head (native clkcpu read side, no sync) |
| in | `phys_media_ready`, `phys_index`, `phys_track0`, `phys_wprot`, `phys_change`, `phys_motor_on`, `phys_head_settled` | live levels, 2-FF synced at `fdc:205-211` |
| out (reg) | `phys_dbg_lost/drain/staledone/busycmd/fin_tgl`, `phys_dbg_pres_cnt[10:0]` | never-reset event toggles for the diag device |

Read-op sequence (the template a write op must mirror):
1. Issue (`fdc:967-979` / verify `fdc:916-927` / read address `fdc:1110-1119`): load params, `phys_rd_seq++`, toggle `phys_rd_req_tgl`, set `phys_rd_pending`, `phys_reading` (not for verify), `phys_rd_start` (re-arms pace, clears `phys_pres_cnt`/`phys_lost_l`).
2. Controller accepts (`ctl:718-754`), runs, pushes bytes, toggles `rd_done_tgl_o` with `rd_done_seq_o <= seq_r` (nine sites, all in `main_p`).
3. WD latches the result on the 2-cycle-delayed synced edge only if `phys_rd_pending && phys_rd_done_seq_c == phys_rd_seq` (`fdc:1195-1212`); else `phys_dbg_staledone_tgl`. An error done drops `phys_reading` so the drain discards the quarantined bytes (`fdc:1205-1206`, `fdc:1584-1590`).
4. Presentation (`fdc:314-317`, `fdc:1543-1565`): `phys_present_now = phys_mode && phys_reading && phys_done_latched && !rnf && !crc && pace_cnt == 0 && !phys_byte_empty && !phys_cpu_rd_data_open && !cpu_rw_data`; each pop loads `data_out`, pulses `phys_byte_rd_en`, `drq_set`, reloads `phys_pace_cnt <= 251`; if DRQ was still set -> `phys_lost_l` + `phys_dbg_lost_tgl`. Pace holds at 0 across the CPU-read deferral.
5. Finalize (`fdc:1236-1262`): `phys_done_latched && phys_byte_empty && pace == 0 && !phys_present_now (&& T1 min for verify)` -> `RNF <= phys_rnf_l`, `phys_dbg_fin_tgl`, multi-sector reissue (`fdc:1249-1254`) or `busy <= 0; irq_set <= 1` (+ `phys_set_sector` for Read Address). BUSY thus outlives the last DRQ by >= one byte-time.
6. Status in phys mode (`fdc:1710-1728`): b6 see §0; b5 `phys_del_l` for reads; b4 `RNF & ~phys_crc_l` (never CRC+RNF together, the `\$CD5A` hole); b3 `phys_crc_l`; b2 `phys_lost_l`; b1 DRQ.

Toggle discipline to copy: request toggles are not reset on `floppy_reset` (phantom-edge avoidance, `fdc:328-343`); `*_serviced` trackers are re-armed to the current synced value on reset (`fdc:718-719`); `c1581_multi.sv:242-307` collects toggles per drive and re-toggles a module-level output only on a real event of the drive in phys mode (new toggles must be added to that collector, `c1581_multi.sv:292-307`, and to the three port lists `iec_drive.sv:74-119`, `c1581_multi.sv:73-116`, `c1581_drv.sv:67-111`).

## 2. c1581_drv.sv / c1581_multi.sv — CIA senses in phys mode

| CIA line | Wiring | Lines |
| --- | --- | --- |
| PB6 /WPRT | `pb_in[6] = phys_mode ? ~phys_wprot_s : wps_n` (`phys_wprot` 2-FF synced into `clk`) | `c1581_drv.sv:152-154`, `:215` |
| PA7 /DSKCHG | `pa_in[7] = phys_mode ? ~phys_change_s : disk_chng_n` | `c1581_drv.sv:206` |
| PA1 /RDY | `pa_in[1] = ~floppy_ready`; `floppy_ready = phys_mode ? phys_media_ready_c : (fd_ready && fd_present)` | `c1581_drv.sv:206`, `fdc:601` |
| PA2 motor | `motor_n = pa_out[2]` -> `.floppy_motor(~motor_n)` -> `phys_cia_motor_on = floppy_motor` -> `ctl` `f_motora_o <= '0' when en and motor_s` | `c1581_drv.sv:200,326`, `fdc:324`, `ctl:351` |
| PA0 side | `side = pa_out[0]` -> `.floppy_side(~side)` -> `phys_cia_side` -> `ctl` `f_side1_o <= not side_s` (= PA0; empirical mapping comment `ctl:352-363`) | `c1581_drv.sv:201,323`, `fdc:325`, `ctl:364` |
| image disk-change | `disk_chng_n` also asserted on any `phys_mode` edge | `c1581_drv.sv:309-314` |

fdc1772's write-protect input is `img_wp(~wps_n)` (`c1581_drv.sv:336`) and is image-only; in phys mode the chip uses `phys_wprot_c` (Type I) or the forced 1 (writes). `c1581_multi.sv:274-277` picks the one drive with `phys_mode[k]` set (onehot from `main.vhd:2070-2078`, sequenced with a 255-cycle all-zero gap at `main.vhd:2081-2095`, `C_PHYS_SWITCH_GAP`).

## 3. VHDL side

### 3.1 main.vhd
- Ports: `c64_rst_sd_i` (QNICE-domain reset) `main.vhd:182`; `f_rdata_i .. f_density_o` `main.vhd:183-193`; diag device `main.vhd:198-200`. **No `f_wgate`/`f_wdata` anywhere in main.vhd or mega65.vhd** (grep: zero hits).
- `phys_1581_en(i) <= '1' when drive_mode_i(2i+1 downto 2i) = "10"` `main.vhd:2049`; onehot 2070-2078; switch sequencer 2081-2095.
- `iec_drive` instance `main.vhd:2104-2204` (`ce => iec_drive_ce` 2105, `clk_sys => c64_clk_sd_i` 2123, `physical_mode => phys_1581_en_q` 2157, phys ports 2160-2204, `phys_byte_ovf => open` 2172).
- Controller instance `main.vhd:2215-2315`: `G_CAPABLE => true`; `clk_i => c64_clk_sd_i, rst_i => c64_rst_sd_i`; pins 2224-2234; mode 2237-2239; step 2242-2244; read op 2247-2263; FIFO write side `byte_data_o/byte_wr_o/byte_ovf_i => p1581_fifo_wr_data/_en/_full` 2266-2268; `st_*` 2271-2279; diag taps 2282-2314.
- rdfifo `main.vhd:2317-2345`: `G_AW => 9` (512 B quarantine); `wr_clk_i => c64_clk_sd_i`, `rd_clk_i => clk_main_i`, `rd_rst_i => p1581_fiforst_s` (QNICE reset synced, never `reset_core_n` alone — comment 2332-2337).
- diag `main.vhd:2354-2438` (`qnice_ce_i => phys_diag_ce_i`, 8-bit word address).
- The fdc1772 dbg toggles are 2-FF synced into the 50 MHz domain at `main.vhd:944-961` and counted inside the diag.

### 3.2 mega65.vhd
- Ports `mega65.vhd:180-193` (comment: "the write pins (f_wgate/f_wdata) and drive-B pins stay tied inactive at the top level"); passed to `main` at `mega65.vhd:893-903`; `C_DEV_C64_PHYS1581` decode `mega65.vhd:1166-1168`; `globals.vhd:94` `C_DEV_C64_PHYS1581 = x"0108"`.

### 3.3 Board tops — the exact lines to change

| Board | entity f_* ports | tie-off block (delete the 2 lines) | CORE port map (add 2 lines) |
| --- | --- | --- | --- |
| `M2M/vhdl/top_mega65-r3.vhd` | 171-185 | `:474 f_wdata_o <= '1';` `:475 f_wgate_o <= '1';` (block 468-475) | 859-869 |
| `M2M/vhdl/top_mega65-r4.vhd` | 183-197 | `:506` / `:507` (block 501-507) | 907-917 |
| `M2M/vhdl/top_mega65-r5.vhd` | 191-205 | `:545` / `:546` (block 540-546) | 946-956 |
| `M2M/vhdl/top_mega65-r6.vhd` | 191-205 | `:545` / `:546` (block 540-546) | 946-956 |

All four tops declare all 16 pins (`f_motorb_o`, `f_selectb_o` stay `'1'`; drive B unused). r3 vs r6 differ only in line numbers and indentation of this block. XDC: `M2M/MEGA65-R3.xdc:228-242` and `M2M/MEGA65-R6.xdc:255-269` — plain `IOSTANDARD LVCMOS33`, no `PULLUP`/`PULLTYPE`/`DRIVE`/`SLEW` properties; `f_wdata_o` = N4 (`F_WDATE`), `f_wgate_o` = N3 (`F_WGATE`), `f_writeprotect_i` = P2 (`F_WPT`). Same package pins on both boards; no XDC change needed.

### 3.4 AExp — the diff to copy

AExp does not use the words "M2M exception 7"; its marker is `M2M-UPSTREAM floppy-pins (AExp 2026-07-26)`.

`/Users/mirko/Documents/Privat/GNR/dev/MEGA65/AExp/M2M/vhdl/top_mega65-r3.vhd:468-477` (tie-off block keeps only drive B):
```vhdl
   -- M2M-UPSTREAM floppy-pins (AExp 2026-07-26): the drive A pins of the
   -- internal floppy connector are routed into MEGA65_Core for the Hardware
   -- Floppy: f_density/f_motora/f_selecta/f_side1/f_stepdir/f_step, the write
   -- pins f_wdata/f_wgate and the five inputs. The core drives f_wdata and
   -- f_wgate from physical_fdd_writer; both idle high (inactive), and WGATE
   -- opens only while, among other conditions, the write-protect tab of the
   -- disk reads writable. Drive B stays tied inactive: the core uses drive A
   -- only.
   f_motorb_o    <= '1';
   f_selectb_o   <= '1';
```
and the CORE port map `:839-853`:
```vhdl
         -- M2M-UPSTREAM floppy-pins (AExp 2026-07-26): MEGA65 internal
         -- floppy drive (Hardware Floppy, read and write)
         f_wdata_o         => f_wdata_o,
         f_wgate_o         => f_wgate_o,
         f_motora_o        => f_motora_o,
         ...
```
(r6: tie `:547-548`, map `:928-929`.) `AExp/CORE/vhdl/mega65.vhd:204-220` declares `f_wdata_o : out std_logic; f_wgate_o : out std_logic;` next to the other f_* ports and `:1632-1642` drives them from `physical_fdd_top` (`f_wdata_o => f_wdata_o, f_wgate_o => f_wgate_o`). Equivalent change here: add the two `out` ports to `MEGA65_Core` (`mega65.vhd:180-193`) and to `main` (`main.vhd:183-193`), route them to the controller, and give the controller two outputs with `:= '1'` defaults (like `f_step_o`, `ctl:58-63`).

## 4. physical_1581_controller.vhd

- **Generics** `ctl:30-44` (50 MHz cycles): `G_READY_WD_CYC 55M` (1.10 s readiness watchdog), `G_DIR_SETUP_CYC 1200` (24 us), `G_STEP_LOW_CYC 200` (4 us), `G_STEP_REC_CYC 150k` (3 ms), `G_STEP_REV_CYC 200k` (4 ms reversal), `G_SETTLE_CYC 900k` (18 ms), `G_SIDE_SETTLE_CYC 5000` (100 us), `G_DAM_TIMEOUT_CYC 68800` (43 byte-times), `G_SEARCH_WD_CYC 65M` (1.3 s), `G_SEARCH_EDGES 5`, `G_PERIOD_MAX_CYC 12.5M` (250 ms). The closed-loop tb overrides only `G_READY_WD_CYC => 150_000_000`, `G_SEARCH_EDGES => 3`, `G_PERIOD_MAX_CYC => 12_500_000` (`tb_physical_1581_controller.vhd:99-104`); flux itself cannot be accelerated.
- **Ports** `ctl:46-166`: pins 51-62 (outputs default `'1'`); `phys_active_i`, `cia_motor_on_i`, `cia_side_i` 65-67; step `step_req_tgl_i/step_outward_i/step_ack_tgl_o` 70-72; read `rd_req_tgl_i, rd_op_i, rd_track_i, rd_side_i, rd_sector_i, rd_seq_i, rd_cancel_tgl_i, rd_done_tgl_o, rd_done_seq_o, rd_result_o, rd_crc_err_o, rd_rnf_o, rd_deleted_o, rd_c/h/r/n_o` 81-97; FIFO `byte_data_o, byte_wr_o, byte_ovf_i` 100-102; `st_media_ready/index/track0/wprot/change/motor_on/head_settled/head_cyl/locked_o` 105-113; diag taps 125-165.
- **Output drivers** `ctl:350-367` (`f_density_o <= '1'` always; everything else forced `'1'` when `en = '0'`); `st_wprot_o <= wprot_c` `ctl:373` (conditioned pin level, no latch — the controller has no write-protect state machine at all; "st_wprot" is a pure sense).
- **Sub-blocks**: `physical_1581_inputs` (2-FF sync, index edge/period/width, `track0_c/wprot_c/change_c`) `ctl:306-316`; `physical_1581_mfm_decoder` `ctl:318-345`; `sync_p` `ctl:453-464` (`active/motor/side` levels, `stq/rdq/cnq` toggles).
- **`main_p`** `ctl:468-962`:
  - reset / `en = '0'` branch `ctl:495-532`: FSMs idle, `media_ready <= 0`, `head_settled <= '1'` (at rest = settled), `change_latched <= '1'` re-armed on every disable (image->internal switch presents as a disk change).
  - disk-change sticky latch `ctl:535-539` (`change_c` sets it and clears `rotation_confirmed`); cleared only in `SI_REC` after a real step with media present `ctl:688-691`.
  - side settle + decoder reset on side change `ctl:543-549`.
  - media-ready model `ctl:553-616`: `motor_on_act <= motor_s`; ready when motor on AND (>= 2 index edges, or 1 edge if `rotation_confirmed` and no change) `ctl:577-583`; motor off clears everything `ctl:587-591`; no index for 2 x `G_PERIOD_MAX_CYC` -> not ready (eject) `ctl:601-614`.
  - head-settle timer `ctl:619-626`; `head_settled <= '0'` on step acceptance `ctl:637`, `'1'` when `settle_cnt` reaches 1.
  - STEP engine `ctl:629-694`: `SI_IDLE` 632 (latch dir, detect reversal, clear settled) -> `SI_SETUP` 647 (DIR setup) -> `SI_LOW` 656 (STEP low 4 us; on trailing edge move `head_cyl`, start 18 ms settle, pick 3/4 ms recovery) -> `SI_REC` 678 (anchor `head_valid` on track0, `step_ack_tgl_o` toggle, clear change latch).
  - READ engine `ctl:697-937`: `done_gap_cnt` (`C_DONE_GAP = 8`, min done spacing) 700-703; global cancel/disk-change abort 705-716 (`RES_DISK_CHANGED` with rnf, or `RES_CANCELLED`); `RD_IDLE` 718 (accept live edge or pending latch, `rdy_wd_cnt` armed); `RD_WAIT` 756 (needs `media_ready && head_settled && side_settle = 0`, else `RES_NOT_READY` on watchdog); `RD_SEARCH` 771 (ID match: Read Address takes next ID with R in 1..10; Verify matches C; Read Sector matches C and R, N must be 2; 5 index edges / 1.3 s -> `RES_RECORD_NOT_FOUND` or `RES_ID_CRC_ERROR`, never both flags); `RD_DAM` 850 (43 byte-time window, else back to search; `RES_MISSING_DAM`); `RD_STREAM` 870 (pushes `data_byte` to FIFO, `data_end` -> CRC verdict; FIFO overflow -> `RES_DATA_CRC_ERROR`); `RD_ADDR` 910 (6 reply bytes C,H,R,N,CRC); pending latch 940-955.
- **Where a write op plugs in**: a parallel `wr_st_t` engine (or new `RD_*`-style states) started from `RD_IDLE`-like acceptance, reusing `RD_WAIT` preconditions plus `wprot_c = '0'` and `change_latched = '0'` (else complete with `RES_WRITE_PROTECTED = "01001"` / `RES_DISK_CHANGED`, codes already in `physical_1581_pkg.vhd:175-188`), `RD_SEARCH`'s ID match for the target sector, then a timed gap (22 byte-times after the ID CRC per `fdc:182-186`) before asserting `f_wgate_o` and streaming an encoder. The `rd_done_tgl_o/rd_done_seq_o` sites (`ctl:712`, 765, 806, 814, 844, 864, 881, 904, 929) show the required done discipline; the HANDOVER mandates (`doc/dev-fdd/HANDOVER.md:411-419`): underrun pads zeros to sector end + LOST DATA, never tear WGATE mid-sector, WGATE kill on raw WP/change (`outer_write_kill`), every backstop bumps a diag counter.

## 5. Diag map and device ID

`physical_1581_diag.vhd`: `C_MAP_VERSION = x"07"` (`:245`), `C_CAPABILITY = x"FF"` with bit0 = **read-only** (`:246-253`; all eight capability bits are already assigned, so a write milestone must clear bit0 and bump the version). Word map (16-bit word offsets, `qnice_addr_i` is 8 bits; reserved offsets read 0):

- `0x00` SIGNATURE (`x"1581"`), `0x01` VERSION/CAPS, `0x02` LIVE_IN, `0x03` LIVE_OUT, `0x04` CTRL_STATE, `0x05` HEAD, `0x06` LAST_RESULT, `0x07` CHRN_CR, `0x08` CHRN_HN, `0x09` ID_STORED_CRC, `0x0A` ID_CALC_CRC, `0x0B` DATA_CALC_CRC, `0x0C` CRC_FLAGS, `0x0D-0x10` IDX_PERIOD/WIDTH lo/hi, `0x11-0x13` GAP_LAST/MIN/MAX,
- 32-bit counters (lo/hi pairs): `0x14` IDX_RAW, `0x16` IDX_QUAL, `0x18` STEP, `0x1A` READOP, `0x1C` RNF, `0x1E` CRCERR, `0x20` CANCEL, `0x22` CHANGE, `0x24` IDDEC, `0x26` GAPERR,
- `0x28` IMG_DRIVE, `0x29` TRC_CNT, map v4: `0x2A` FIFO_LEVEL, `0x2B` LAST_PRESENT, `0x2C` LOST, `0x2E` DRAIN, `0x30` STALEDONE, `0x32` BUSYCMD, `0x34` RUNT (lo/hi), map v5: `0x36` EST, `0x37` RNF_CTX, map v6: `0x38-0x3A` A1_CAND/REJECT/TRAIN, map v7: `0x3B-0x3F` MARK_FE/MARK_DAM/DAM_UNARMED/MATCH_ID/DAM_MISS, `0x40-0x7F` trace ring (entry k at `0x40+2k`).
- **Free for the write milestone: `0x80-0xFF`** (nothing below 0x80 is unused). `LIVE_OUT` (`ctl:445-449`) packs 7 bits (motor, select, side, dir, step, density, en) — bits 7+ are free for `wgate`/`wdata` levels.
- `globals.vhd:94`: `C_DEV_C64_PHYS1581 = x"0108"` ("read-only diag register bank"); next free device id after `x"010B"` (RR-Net).

## 6. Testbenches and build recipes

`CORE/vhdl/test/tb_physical_1581_controller/`:
- `golden_1581_pkg.vhd` (61 lines): pure `lba1581(cyl,side,sec)` and `golden_payload(cyl,side,sec,off)`; the same source of truth generates the flux and the expected bytes.
- `mech_model_1581.vhd` (217 lines, sim-only): observes `f_motora/f_selecta/f_side1/f_stepdir/f_step/f_density`, drives `f_index/f_track0/f_writeprotect/f_diskchanged/f_rdata` (active-low), `cfg_present/wprot/change_i`, `cur_cyl_o`. Head tracking `:75-92`; static sensors `:109-119`; index `:127-139`; **flux `:147-215`: regenerates the whole track per revolution from `golden_payload` with `mfm_bytes/mfm_a1/mfm_byte` from `tb_physical_1581_codec/mfm_flux_gen_pkg.vhd`** (12x00, 3xA1, FE, CHRN, CRC, 22x4E, 12x00, 3xA1, FB, 512 B, CRC, 30x4E). **It has no writable surface, no `f_wgate_i`/`f_wdata_i` ports, no stored flux array** — the RDATA stream is procedurally generated, not played back from memory. Extending it for writes means adding `f_wgate_i`/`f_wdata_i`, a per-(cyl,side) byte/flux store that the flux process reads instead of `golden_payload`, and a WDATA pulse recorder (gap-quantise + MFM decode, or feed the recorded flux back through the real decoder as the existing tb does for reads).
- `tb_mech_model_1581.vhd`: model vs real decoder self-test (exact GHDL command list in its header `:17-31`).
- `tb_physical_1581_controller.vhd` (401): closed-loop controller + rdfifo (`G_AW => 6`) + mech model; covers restore/media-ready/Read Sector x2/Read Address/Verify/Step/RNF/seq tags/pending latch/abort spacing/F4 monitor (header `:1-30`).
- `tb_physical_1581_media_contract.vhd` (253): drives INDEX/RDATA directly; two-edge vs one-edge readiness, change/disable clearing history, Read Address ignores sector 11.
- `tb_physical_1581_ovf.vhd` (145): 4-entry FIFO never drained -> must end `RES_DATA_CRC_ERROR` with rnf clear.
- Other suites: `tb_physical_1581_codec/` (crc, mfm_decoder, quantise A/B + `ref_mfm_quantise_fixed`), `tb_physical_1581_inputs/` (inputs, rdfifo), `tb_physical_1581_diag/`.

`CORE/C64_MiSTerMEGA65/rtl/iec_drive/tb_fdc1772_physical.sv` (1339 lines, iverilog): fdc1772 with `phys_mode=1`, a `floppy` stub, an SV Gray FIFO and a mock backend on a 50 MHz-ish clock; 13 scenario groups (header `:21-74`): register readback, Read Address/Read Sector byte-exact with the ROM `\$CD17` polling idiom, stalled CPU -> LOST DATA, residue drain, busy-cmd ignore, FI + stale done, CRC/RNF never together, busy tail, read-access deferral, FI/reissue collision, zero-step Type-I min busy, CRC quarantine, short-select. **No phys-mode Write Sector / Write Track scenario exists** (grep for `3'b101`/`A0`/`F0` writes: none). Run: `iverilog -g2012 -o tb.vvp tb_fdc1772_physical.sv fdc1772.v iecdrv_misc.sv && vvp tb.vvp` (`:70-72`).

GHDL recipe, `doc/dev-fdd/PLAN.md:82-86` ("GHDL build recipe (codec)"):
```
B=<tmpdir>; ghdl -a --std=08 --workdir=$B CORE/vhdl/physical_1581/{physical_1581_pkg,_crc,_mfm_gaps,
_mfm_quantise,_mfm_gaps_to_bits,_mfm_bits_to_bytes,_mfm_decoder}.vhd \
CORE/vhdl/test/tb_physical_1581_codec/{mfm_flux_gen_pkg,tb_physical_1581_mfm_decoder}.vhd ;
ghdl --elab-run --std=08 --workdir=$B <tb> --assert-level=error   (no `timeout` on macOS; tbs self-bound)
```
(the brace expansion as written needs the `physical_1581` prefix on every file; the controller suite additionally analyzes `physical_1581_inputs.vhd`, `physical_1581_rdfifo.vhd`, `physical_1581_controller.vhd`, then `golden_1581_pkg.vhd`, `mech_model_1581.vhd` and the tb — the exact per-file list is in `tb_mech_model_1581.vhd:17-31`). GHDL `--elab-run` drops `tb_*`/`e~tb_*.o` executables in the cwd (`HANDOVER.md:443-446`): run from a scratch dir or clean up.

## 7. Checklist derived from the above (what the write milestone has to touch)

1. `fdc`: replace the fake-finishes at `:980-984` (Write Sector) and `:1122-1124` (Write Track) by a `phys_wr_*` request mirroring 1.6 (seq tag, pending, done-latched finalize, `phys_cmd_clear`); feed bytes from the data register into a write FIFO at `clk8m_en` byte pace with LOST-DATA-on-underrun; drop the forced WP term at `:1711` in favor of a real `phys_wprot_c`-based completion; keep CRC and RNF mutually exclusive.
2. `c1581_drv.sv:67-111`, `c1581_multi.sv:73-116` + collectors `:292-307`, `iec_drive.sv:74-119`: thread the new ports.
3. `main.vhd:2104-2204` / `:2215-2315`: new ports, a write FIFO (reverse of `physical_1581_rdfifo`, `clk_main_i` write side / 50 MHz read side), `f_wgate_o`/`f_wdata_o` out of `main`, `mega65.vhd`, and the four tops (§3.3).
4. `ctl`: write engine (§4), `RES_WRITE_PROTECTED` path, WGATE safety, diag taps; `physical_1581_diag.vhd`: map v8, cap bit0 cleared, words from `0x80`.
5. Tests: extend `mech_model_1581` with a writable surface (§6); add phys-mode write scenarios to `tb_fdc1772_physical.sv`.
