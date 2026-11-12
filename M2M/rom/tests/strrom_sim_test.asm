; ****************************************************************************
; MiSTer2MEGA65 (M2M) QNICE ROM
;
; Testbed for the string ROM (../strrom.asm, device M2M$STRROM)
;
; Unlike most of the other testbeds, this one does not run in the QNICE
; emulator, which has no M2M devices: strrom_sim_test.py builds it as a
; self-contained RELEASE-style ROM (QNICE Monitor at 0x0000, exactly like
; m2m-rom.asm), using the tool that also builds the real firmware,
; M2M/tools/asm_strrom.sh, and runs it on the real QNICE CPU inside the real
; M2M/vhdl/qnice_wrapper.vhd in a ghdl simulation (strrom_sim_tb.vhd).
;
; The firmware contains the real ../tools.asm and ../screen.asm, the real
; strings of the Shell and strings that are made to hit the edge cases of the
; string ROM. It does not check anything by itself. It reports what it reads
; and what the routines under test do, and strrom_sim_test.py compares that
; with values that it derives from the sources:
;
; * The complete content of the string ROM, read via the 4k window
; * STRROM$OPEN and STRROM$CLOSE for every handle and for values that are no
;   handles: R8, the selected device and 4k window, the stack pointer, the
;   registers of the caller and the Carry and the Overflow flag
; * IO$PUTS (the puts of the QNICE Monitor), LOG_STR and SCR$PRINTSTR for
;   handles and for ordinary strings in the ROM, in the RAM and in the 4k
;   window of a device: the characters that are sent to the UART and those
;   that are written to the video RAM; IO$PUTS: the Carry and the Overflow flag
;
; strrom_sim_test.py generates strrom_sim_fixtures.asm, which is included
; below, on every run. It contains the records of the case table for the
; handles, the tables SST_JOBSEC and SST_PRESETS, the constant SST_WINDOWS,
; the real string ROM strings of the Shell and strings of exactly the lengths
; that are needed to place a string at the end of a 4k window, to make the
; next one too long by one character and to fill a whole 4k window with one
; string.
;
; Reporting: The testbench provides three ports in the address range of the
; UART that the real UART ignores (see the architecture sim of bus_uart in
; strrom_sim_tb.vhd). Each word that is written to SST_P_LOG or SST_P_MARK
; becomes a line of the simulation output; markers structure the output.
; Writing 1 to SST_P_CTRL switches the UART to turbo mode: characters are
; reported, but not transmitted with 115,200 baud any more. The second word of
; M2M$CFD_DATA requests a dump of the video RAM and the first word ends the
; simulation: 0x600D after the last test, 0xDEAD if FATAL was called.
;
; The simulation is slow. Therefore the test can be split into up to five
; jobs that run as separate simulations: the testbench applies the number of
; the job to the keyboard input of QNICE, where the firmware reads it.
;
; done by sy2002 in 2026 and licensed under GPL v3
; ****************************************************************************

#define RELEASE
#include "../main.asm"

; ----------------------------------------------------------------------------
; Constants
; ----------------------------------------------------------------------------

; Ports of the testbench
SST_P_CTRL      .EQU 0xFF10                     ; bit 0: turbo mode of the UART
SST_P_LOG       .EQU 0xFF11                     ; log port: data
SST_P_MARK      .EQU 0xFF12                     ; log port: markers

; Markers
SST_MK_START    .EQU 0xA000                     ; + number of the job
SST_MK_SERIAL   .EQU 0x5E00                     ; + number of the string
SST_MK_TURBO    .EQU 0x7B00
SST_MK_CLR      .EQU 0xC1EA
SST_MK_DUMP     .EQU 0xD000                     ; + number of the 4k window
SST_MK_PROBE    .EQU 0xD100
SST_MK_WRITE    .EQU 0xD200
SST_MK_OPEN     .EQU 0x0B00
SST_MK_NEST     .EQU 0x0B10                     ; + number of the sequence
SST_MK_WALK     .EQU 0x0C00
SST_MK_CASE     .EQU 0xCA00                     ; + number of the routine
SST_MK_VRAM     .EQU 0x0D00
SST_MK_END      .EQU 0xE0D0
SST_MK_FATAL    .EQU 0xFA7A

; Sections of the test: bits of the words in SST_JOBSEC
SST_SEC_SERIAL  .EQU 0x0001                     ; strings via the real UART
SST_SEC_VRAM    .EQU 0x0002                     ; SCR$CLR and video RAM readback
SST_SEC_DUMP    .EQU 0x0004                     ; content of the string ROM
SST_SEC_OPEN    .EQU 0x0008                     ; STRROM$OPEN and STRROM$CLOSE
SST_SEC_WALK    .EQU 0x0010                     ; read every handle

; Routines of a case: bits of the first word of a record of the case table.
; Bits 0 to 2 belong to job 0, bits 3 to 5 to job 1 and so on.
SST_RT_PUTS     .EQU 0x0001                     ; IO$PUTS
SST_RT_LOG      .EQU 0x0002                     ; LOG_STR
SST_RT_SCR      .EQU 0x0004                     ; SCR$PRINTSTR
SST_RT_ALL      .EQU 0x0007                     ; all of them in job 0
SST_CASE_SIZE   .EQU 7                          ; words per record

; Ordinary strings outside of the ROM
SST_RAMSTR      .EQU 0x9000                     ; in the RAM
SST_DEV         .EQU 0x0100                     ; device of the testbench
SST_DEV_WIN     .EQU 0xFFFF                     ; its only 4k window
SST_DEVSTR      .EQU 0x7100                     ; in the window of the device
SST_DEVSTR_END  .EQU 0x7FF8                     ; ditto, SST_O_END ends at the
                                                ; last address of the window

SST_VRAM_CELLS  .EQU 96                         ; video RAM readback: amount

SST_FLAGS       .EQU 0x0024                     ; Carry and Overflow flag in SR

; ----------------------------------------------------------------------------
; Main program
; ----------------------------------------------------------------------------

                ; The register file of the simulated CPU starts undefined, so
                ; the idiom XOR Rx, Rx would yield X instead of 0 as on the
                ; hardware: clear R0..R7 of all 64 register banks of the M2M
                ; QNICE (SHADOW_REGFILE_SIZE in qnice_globals.vhd) from bank
                ; 63 down to bank 0, and R8..R12
START_FIRMWARE  MOVE    64, R8
_SST_RB         SUB     1, R8                   ; R8: bank 63 .. 0
                MOVE    R8, R9
                SWAP    R9, R9                  ; bank number to the high byte
                AND     0x00FF, SR              ; select the bank
                OR      R9, SR
                MOVE    0, R0
                MOVE    0, R1
                MOVE    0, R2
                MOVE    0, R3
                MOVE    0, R4
                MOVE    0, R5
                MOVE    0, R6
                MOVE    0, R7
                CMP     0, R8
                RBRA    _SST_RB, !Z
                MOVE    0, R9
                MOVE    0, R10
                MOVE    0, R11
                MOVE    0, R12

                RSUB    SCR$INIT, 1             ; size of the screen from the
                                                ; sysinfo device and config.vhd

                MOVE    M2M$KEYBOARD, R0        ; R0: number of the job
                MOVE    @R0, R0
                MOVE    SST_V_JOB, R1
                MOVE    R0, @R1

                MOVE    SST_RT_PUTS, R1         ; routine bits of this job:..
                CMP     0, R0                   ; ..three bits per job
                RBRA    _SST_I2, Z
_SST_I1         ADD     R1, R1
                ADD     R1, R1
                ADD     R1, R1
                SUB     1, R0
                RBRA    _SST_I1, !Z
_SST_I2         MOVE    SST_V_MPUTS, R2
                MOVE    R1, @R2
                ADD     R1, R1
                MOVE    SST_V_MLOG, R2
                MOVE    R1, @R2
                ADD     R1, R1
                MOVE    SST_V_MSCR, R2
                MOVE    R1, @R2

                MOVE    SST_V_JOB, R0           ; sections of this job
                MOVE    @R0, R0
                MOVE    R0, R1
                ADD     SST_JOBSEC, R1
                MOVE    SST_V_SEC, R2
                MOVE    @R1, @R2

                MOVE    SST_V_PRE, R1           ; first entry of SST_PRESETS
                MOVE    SST_PRESETS, @R1

                MOVE    SST_P_MARK, R1          ; report the start
                ADD     SST_MK_START, R0
                MOVE    R0, @R1
                MOVE    SST_P_LOG, R1
                MOVE    STRROM$TAB, @R1
                MOVE    STRROM$TAB_END, @R1
                MOVE    SCR$SYS_DX, R0
                MOVE    @R0, @R1
                MOVE    SCR$SYS_DY, R0
                MOVE    @R0, @R1

                ; Copy the ordinary strings that are not read from the ROM to
                ; their places
                MOVE    SST_COPY, R0
_SST_CP1        MOVE    @R0++, R1               ; R1: source
                RBRA    _SST_DUMP, Z
                MOVE    @R0++, R2               ; R2: destination
                MOVE    M2M$RAMROM_DEV, R3
                MOVE    @R0++, @R3
                MOVE    M2M$RAMROM_4KWIN, R3
                MOVE    @R0++, @R3
_SST_CP2        MOVE    @R1++, @R2++
                RBRA    _SST_CP2, !Z
                RBRA    _SST_CP1, 1

                ; ------------------------------------------------------------
                ; Content of the string ROM: all 4k windows
                ; ------------------------------------------------------------

_SST_DUMP       MOVE    SST_V_SEC, R0
                MOVE    @R0, R0
                AND     SST_SEC_DUMP, R0
                RBRA    _SST_OPEN, Z

                MOVE    M2M$RAMROM_DEV, R0
                MOVE    M2M$STRROM, @R0
                MOVE    M2M$RAMROM_4KWIN, R0    ; R0: 4k window selector
                MOVE    SST_P_LOG, R3           ; R3: log port
                MOVE    SST_P_MARK, R4          ; R4: marker port
                XOR     R1, R1                  ; R1: current window

_SST_D1         MOVE    R1, @R0
                MOVE    R1, R2
                ADD     SST_MK_DUMP, R2
                MOVE    R2, @R4
                MOVE    M2M$RAMROM_DATA, R2
_SST_D2         MOVE    @R2++, @R3
                MOVE    @R2++, @R3
                MOVE    @R2++, @R3
                MOVE    @R2++, @R3
                MOVE    @R2++, @R3
                MOVE    @R2++, @R3
                MOVE    @R2++, @R3
                MOVE    @R2++, @R3
                CMP     0x8000, R2              ; end of the 4k window
                RBRA    _SST_D2, !Z
                ADD     1, R1
                CMP     SST_WINDOWS, R1
                RBRA    _SST_D1, !Z

                ; windows behind the end of the string ROM: the first two and
                ; the last two addresses of each of them
                MOVE    SST_MK_PROBE, @R4
                MOVE    SST_PROBES, R5
_SST_D3         MOVE    @R5++, @R0
                MOVE    M2M$RAMROM_DATA, R2
                MOVE    @R2++, @R3
                MOVE    @R2, @R3
                MOVE    0x7FFE, R2
                MOVE    @R2++, @R3
                MOVE    @R2, @R3
                CMP     SST_PROBES_END, R5
                RBRA    _SST_D3, !Z

                ; the string ROM ignores write accesses
                MOVE    SST_MK_WRITE, @R4
                MOVE    0, @R0
                MOVE    M2M$RAMROM_DATA, R2
                MOVE    @R2, R1
                MOVE    R1, @R3
                NOT     R1, R1
                MOVE    R1, @R2
                MOVE    @R2, @R3

                ; ------------------------------------------------------------
                ; STRROM$OPEN and STRROM$CLOSE
                ; ------------------------------------------------------------

_SST_OPEN       MOVE    SST_V_SEC, R0
                MOVE    @R0, R0
                AND     SST_SEC_OPEN, R0
                RBRA    _SST_WALK, Z

                ; every handle: with Carry and Overflow set and with both
                ; flags clear
                MOVE    SST_V_VAL, R0
                MOVE    STRROM$TAB, @R0
_SST_O1         MOVE    SST_V_FLG, R0
                MOVE    SST_FLAGS, @R0
                RSUB    SST$OPENCASE, 1
                MOVE    SST_V_FLG, R0
                MOVE    0, @R0
                RSUB    SST$OPENCASE, 1
                MOVE    SST_V_VAL, R0
                ADD     1, @R0
                CMP     STRROM$TAB_END, @R0
                RBRA    _SST_O1, !Z

                ; the values of SST_BOUND
                MOVE    SST_V_PTR, R0
                MOVE    SST_BOUND, @R0
_SST_O2         MOVE    SST_V_PTR, R0
                MOVE    @R0, R1
                MOVE    @R1++, R2               ; base
                ADD     @R1++, R2               ; plus offset
                MOVE    R1, @R0
                MOVE    SST_V_VAL, R0
                MOVE    R2, @R0
                MOVE    SST_V_FLG, R0
                MOVE    SST_FLAGS, @R0
                RSUB    SST$OPENCASE, 1
                MOVE    SST_V_FLG, R0
                MOVE    0, @R0
                RSUB    SST$OPENCASE, 1
                MOVE    SST_V_PTR, R0
                CMP     SST_BOUND_END, @R0
                RBRA    _SST_O2, !Z

                ; nested: first handle, then last handle
                MOVE    SST_P_MARK, R0
                MOVE    SST_MK_NEST, R1
                MOVE    R1, @R0
                RSUB    SST$PRESET, 1
                MOVE    STRROM$TAB, R8
                RSUB    SST$LOGSEL, 1
                RSUB    STRROM$OPEN, 1
                RSUB    SST$LOGSEL, 1
                MOVE    STRROM$TAB_END, R8
                SUB     1, R8
                RSUB    STRROM$OPEN, 1
                RSUB    SST$LOGSEL, 1
                RSUB    STRROM$CLOSE, 1
                RSUB    SST$LOGSEL, 1
                RSUB    STRROM$CLOSE, 1
                RSUB    SST$LOGSEL, 1

                ; nested: last handle, then a pointer
                ADD     1, R1
                MOVE    R1, @R0
                RSUB    SST$PRESET, 1
                MOVE    STRROM$TAB_END, R8
                SUB     1, R8
                RSUB    SST$LOGSEL, 1
                RSUB    STRROM$OPEN, 1
                RSUB    SST$LOGSEL, 1
                MOVE    SST_RAMSTR, R8
                RSUB    STRROM$OPEN, 1
                RSUB    SST$LOGSEL, 1
                RSUB    STRROM$CLOSE, 1
                RSUB    SST$LOGSEL, 1
                RSUB    STRROM$CLOSE, 1
                RSUB    SST$LOGSEL, 1

                ; ------------------------------------------------------------
                ; Read every handle via STRROM$OPEN
                ; ------------------------------------------------------------

_SST_WALK       MOVE    SST_V_SEC, R0
                MOVE    @R0, R0
                AND     SST_SEC_WALK, R0
                RBRA    _SST_SERIAL, Z

                MOVE    STRROM$TAB, R4          ; R4: handle
                MOVE    SST_P_MARK, R5
                MOVE    SST_P_LOG, R6
_SST_W1         RSUB    SST$PRESET, 1
                MOVE    SST_MK_WALK, @R5
                MOVE    R4, @R6
                MOVE    R4, R8
                RSUB    STRROM$OPEN, 1
_SST_W2         MOVE    @R8++, @R6              ; including the terminator
                RBRA    _SST_W2, !Z
                RSUB    STRROM$CLOSE, 1
                MOVE    M2M$RAMROM_DEV, R0
                MOVE    @R0, @R6
                MOVE    M2M$RAMROM_4KWIN, R0
                MOVE    @R0, @R6
                ADD     1, R4
                CMP     STRROM$TAB_END, R4
                RBRA    _SST_W1, !Z

                ; ------------------------------------------------------------
                ; A few strings via the real UART: the testbench decodes them
                ; from the pin. From then on the UART runs in turbo mode. The
                ; sections above do not use the UART.
                ; ------------------------------------------------------------

_SST_SERIAL     MOVE    SST_V_SEC, R0
                MOVE    @R0, R0
                AND     SST_SEC_SERIAL, R0
                RBRA    _SST_TURBO, Z

                MOVE    SST_P_MARK, R0
                MOVE    SST_MK_SERIAL, R1
                ADD     1, R1
                MOVE    R1, @R0
                MOVE    SST_S_ONE, R8           ; handle
                SYSCALL(puts, 1)
                ADD     1, R1
                MOVE    R1, @R0
                MOVE    SST_S_UART, R8          ; handle
                RSUB    LOG_STR, 1
                ADD     1, R1
                MOVE    R1, @R0
                MOVE    NEWLINE, R8             ; pointer
                SYSCALL(puts, 1)

_SST_TURBO      MOVE    SST_P_MARK, R0
                MOVE    SST_MK_TURBO, @R0
                MOVE    SST_P_CTRL, R0
                MOVE    1, @R0

                ; ------------------------------------------------------------
                ; SCR$CLR: fills the video RAM
                ; ------------------------------------------------------------

                MOVE    SST_V_SEC, R0
                MOVE    @R0, R0
                AND     SST_SEC_VRAM, R0
                RBRA    _SST_CASES, Z

                MOVE    SST_P_MARK, R0
                MOVE    SST_MK_CLR, @R0
                RSUB    SCR$CLR, 1
                RSUB    SST$VDUMP, 1

                ; ------------------------------------------------------------
                ; Case table: IO$PUTS, LOG_STR and SCR$PRINTSTR
                ; ------------------------------------------------------------

_SST_CASES      MOVE    SST_CASES, R7           ; R7: current record
                XOR     R5, R5                  ; R5: number of the record
_SST_C1         MOVE    @R7, R4                 ; R4: routines of all jobs
                CMP     0xFFFF, R4
                RBRA    _SST_VRAM, Z

                MOVE    SST_V_MPUTS, R0
                MOVE    @R0, R0
                AND     R4, R0
                RBRA    _SST_C2, Z
                MOVE    SST_RT_PUTS, R6
                RSUB    SST$CASE, 1

_SST_C2         MOVE    SST_V_MLOG, R0
                MOVE    @R0, R0
                AND     R4, R0
                RBRA    _SST_C3, Z
                MOVE    SST_RT_LOG, R6
                RSUB    SST$CASE, 1

_SST_C3         MOVE    SST_V_MSCR, R0
                MOVE    @R0, R0
                AND     R4, R0
                RBRA    _SST_C4, Z
                MOVE    SST_RT_SCR, R6
                RSUB    SST$CASE, 1

_SST_C4         ADD     SST_CASE_SIZE, R7
                ADD     1, R5
                RBRA    _SST_C1, 1

                ; ------------------------------------------------------------
                ; Read the video RAM like the Shell does: characters via the
                ; device M2M$VRAM_DATA, attributes via M2M$VRAM_ATTR
                ; ------------------------------------------------------------

_SST_VRAM       MOVE    SST_V_SEC, R0
                MOVE    @R0, R0
                AND     SST_SEC_VRAM, R0
                RBRA    _SST_END, Z

                MOVE    SST_P_MARK, R0
                MOVE    SST_MK_VRAM, @R0
                MOVE    SST_P_LOG, R3
                MOVE    M2M$RAMROM_4KWIN, R0
                MOVE    0, @R0
                MOVE    M2M$RAMROM_DEV, R0
                MOVE    M2M$VRAM_DATA, @R0
                RSUB    _SST_VR1, 1
                MOVE    M2M$VRAM_ATTR, @R0
                RSUB    _SST_VR1, 1
                RBRA    _SST_END, 1

_SST_VR1        MOVE    M2M$RAMROM_DATA, R1
                MOVE    SST_VRAM_CELLS, R2
_SST_VR2        MOVE    @R1++, @R3
                SUB     1, R2
                RBRA    _SST_VR2, !Z
                RET

                ; ------------------------------------------------------------
                ; End of the test
                ; ------------------------------------------------------------

_SST_END        MOVE    SST_P_MARK, R0
                MOVE    SST_MK_END, @R0
                MOVE    0x600D, R1

_SST_HALT       MOVE    M2M$CFD_ADDR, R0        ; R1: result
                MOVE    0, @R0
                MOVE    M2M$CFD_DATA, R0
                MOVE    R1, @R0
                HALT

; ----------------------------------------------------------------------------
; One case of the case table
;
; Selects the device and the 4k window of the record, calls the routine and
; reports R8, the selected device and window and the stack pointer before and
; after the call. SCR$PRINTSTR: sets the cursor and the left margin before
; and reports the cursor and requests a dump of the video RAM after the call.
; IO$PUTS: is called with the Carry and the Overflow flag set (records with an
; even number) or clear (odd number); both flags are reported after the call.
;
; Input:  R7: record, R6: routine (SST_RT_*), R5: number of the record
; Output: R4 to R7 are not changed
; ----------------------------------------------------------------------------

SST$CASE        MOVE    SST_P_MARK, R0
                MOVE    R6, R1
                ADD     SST_MK_CASE, R1
                MOVE    R1, @R0
                MOVE    SST_P_LOG, R0
                MOVE    R5, @R0

                MOVE    R7, R1
                ADD     1, R1
                MOVE    @R1++, R8               ; R8: pointer or handle
                MOVE    M2M$RAMROM_DEV, R2
                MOVE    @R1++, @R2
                MOVE    M2M$RAMROM_4KWIN, R2
                MOVE    @R1++, @R2

                CMP     SST_RT_SCR, R6
                RBRA    _SST_CA1, !Z
                MOVE    SCR$CUR_X, R2
                MOVE    @R1++, @R2
                MOVE    SCR$CUR_Y, R2
                MOVE    @R1++, @R2
                MOVE    SCR$ILX, R2
                MOVE    @R1++, @R2

_SST_CA1        RSUB    SST$LOGSEL, 1

                CMP     SST_RT_PUTS, R6
                RBRA    _SST_CA2, !Z
                MOVE    SST_V_FLG, R0
                MOVE    SST_FLAGS, @R0
                MOVE    R5, R1                  ; even record: flags set
                AND     1, R1
                RBRA    _SST_CA1A, Z
                MOVE    0, @R0                  ; odd record: flags clear
_SST_CA1A       RSUB    SST$SETFLAGS, 1
                SYSCALL(puts, 1)
                RSUB    SST$LOGFLAGS, 1
                RBRA    _SST_CA4, 1
_SST_CA2        CMP     SST_RT_LOG, R6
                RBRA    _SST_CA3, !Z
                RSUB    LOG_STR, 1
                RBRA    _SST_CA4, 1
_SST_CA3        RSUB    SCR$PRINTSTR, 1

_SST_CA4        RSUB    SST$LOGSEL, 1

                CMP     SST_RT_SCR, R6
                RBRA    _SST_CA5, !Z
                MOVE    SST_P_LOG, R0
                MOVE    SCR$CUR_X, R1
                MOVE    @R1, @R0
                MOVE    SCR$CUR_Y, R1
                MOVE    @R1, @R0
                RSUB    SST$VDUMP, 1

_SST_CA5        RET

; ----------------------------------------------------------------------------
; STRROM$OPEN and STRROM$CLOSE for the value in SST_V_VAL
;
; Selects the next device and 4k window of SST_PRESETS, fills the registers
; with known values and reports R8, the selected device and window and the
; stack pointer before STRROM$OPEN, after STRROM$OPEN and after STRROM$CLOSE
; and then R0 to R7 and R9 to R12. STRROM$OPEN is called with the Carry and
; the Overflow flag in the state that SST_V_FLG holds, and both flags are
; reported after STRROM$OPEN and after STRROM$CLOSE: neither of the two
; routines changes them, although STRROM$OPEN shifts and SHR shifts in the
; Carry flag.
;
; Changes all registers. Call it from the main program only: The stack
; pointer is part of the expected values.
; ----------------------------------------------------------------------------

SST$OPENCASE    RSUB    SST$PRESET, 1
                MOVE    SST_P_MARK, R8
                MOVE    SST_MK_OPEN, @R8

                MOVE    0xA0A0, R0
                MOVE    0xA1A1, R1
                MOVE    0xA2A2, R2
                MOVE    0xA3A3, R3
                MOVE    0xA4A4, R4
                MOVE    0xA5A5, R5
                MOVE    0xA6A6, R6
                MOVE    0xA7A7, R7
                MOVE    0xB9B9, R9
                MOVE    0xBABA, R10
                MOVE    0xBBBB, R11
                MOVE    0xBCBC, R12

                MOVE    SST_V_VAL, R8
                MOVE    @R8, R8
                RSUB    SST$LOGSEL, 1
                RSUB    SST$SETFLAGS, 1
                RSUB    STRROM$OPEN, 1
                RSUB    SST$LOGFLAGS, 1
                RSUB    SST$LOGSEL, 1
                RSUB    STRROM$CLOSE, 1
                RSUB    SST$LOGFLAGS, 1
                RSUB    SST$LOGSEL, 1

                MOVE    SST_P_LOG, R8
                MOVE    R0, @R8
                MOVE    R1, @R8
                MOVE    R2, @R8
                MOVE    R3, @R8
                MOVE    R4, @R8
                MOVE    R5, @R8
                MOVE    R6, @R8
                MOVE    R7, @R8
                MOVE    R9, @R8
                MOVE    R10, @R8
                MOVE    R11, @R8
                MOVE    R12, @R8
                RET

; ----------------------------------------------------------------------------
; Selects the next device and 4k window of the list SST_PRESETS
; No registers are changed
; ----------------------------------------------------------------------------

SST$PRESET      INCRB
                MOVE    SST_V_PRE, R0
                MOVE    @R0, R1                 ; R1: next entry of the list
                CMP     SST_PRESETS_END, R1
                RBRA    _SST_PR1, !Z
                MOVE    SST_PRESETS, R1         ; start over
_SST_PR1        MOVE    M2M$RAMROM_DEV, R2
                MOVE    @R1++, @R2
                MOVE    M2M$RAMROM_4KWIN, R2
                MOVE    @R1++, @R2
                MOVE    R1, @R0
                DECRB
                RET

; ----------------------------------------------------------------------------
; Reports R8, the selected device, the selected 4k window and the stack
; pointer of the caller
; No registers are changed and neither are the Carry and the Overflow flag
; ----------------------------------------------------------------------------

SST$LOGSEL      INCRB
                MOVE    SST_P_LOG, R0
                MOVE    R8, @R0
                MOVE    M2M$RAMROM_DEV, R1
                MOVE    @R1, @R0
                MOVE    M2M$RAMROM_4KWIN, R1
                MOVE    @R1, @R0
                MOVE    SP, R1
                MOVE    @R1++, R2               ; skip the return address: an..
                MOVE    R1, @R0                 ; ..ADD would change the flags
                DECRB
                RET

; ----------------------------------------------------------------------------
; Sets the Carry and the Overflow flag to the state that SST_V_FLG holds:
; SST_FLAGS sets both of them, 0 clears both of them
; No registers are changed
; ----------------------------------------------------------------------------

SST$SETFLAGS    INCRB
                MOVE    SST_V_FLG, R0
                MOVE    @R0, R0
                AND     0xFFDB, SR              ; clear both flags..
                OR      R0, SR                  ; ..and set them if wanted
                DECRB
                RET

; ----------------------------------------------------------------------------
; Reports the Carry and the Overflow flag
; No registers are changed and neither are the two flags
; ----------------------------------------------------------------------------

SST$LOGFLAGS    INCRB
                MOVE    SR, R0
                AND     SST_FLAGS, R0
                MOVE    SST_P_LOG, R1
                MOVE    R0, @R1
                DECRB
                RET

; ----------------------------------------------------------------------------
; Requests a dump of the video RAM from the testbench
; No registers are changed
; ----------------------------------------------------------------------------

SST$VDUMP       INCRB
                MOVE    M2M$CFD_ADDR, R0
                MOVE    1, @R0
                MOVE    M2M$CFD_DATA, R0
                ADD     1, @R0
                DECRB
                RET

; ----------------------------------------------------------------------------
; ../tools.asm refers to these labels of the Shell. The routines under test do
; not use any of them.
; ----------------------------------------------------------------------------

FATAL           MOVE    SST_P_MARK, R0
                MOVE    SST_MK_FATAL, @R0
                MOVE    0xDEAD, R1
                RBRA    _SST_HALT, 1

OPTM_SET        RBRA    FATAL, 1

SD_WAIT         .EQU 0x05F6
ASCAL_FILTER_LEN .EQU 0x0100

; ----------------------------------------------------------------------------
; The real routines of the Shell
; ----------------------------------------------------------------------------

#include "../tools.asm"
#include "../screen.asm"

; ----------------------------------------------------------------------------
; Tables
; ----------------------------------------------------------------------------

; Values for STRROM$OPEN that are located at and around the limits of the
; table of the string ROM and that are no handles for sure: base plus offset
SST_BOUND       .DW     STRROM$TAB, 0xFFFF      ; one below the first handle
                .DW     STRROM$TAB, 0           ; first handle
                .DW     STRROM$TAB_END, 0xFFFF  ; last handle
                .DW     STRROM$TAB_END, 0       ; one above the last handle
                .DW     IO$HEX_NIBBLES, 0       ; string in ROM below the table
                .DW     SST_O_ROM, 0            ; string in ROM above the table
                .DW     SST_RAMSTR, 0           ; string in RAM
                .DW     M2M$RAMROM_DATA, 0      ; first address of the window
                .DW     0x7FFF, 0               ; last address of the window
                .DW     0x0000, 0
                .DW     0xFFFF, 0
SST_BOUND_END

; 4k windows behind the end of the string ROM
SST_PROBES      .DW     4, 5, 7, 8, 15, 16, 0x0100, 0x8003, 0xFFFF
SST_PROBES_END

; Ordinary strings that are copied at the start of the test:
; source, destination, device and 4k window to select for the destination
SST_COPY        .DW     SST_O_DW, SST_RAMSTR, M2M$VRAM_DATA, 0
                .DW     SST_O_DW, SST_DEVSTR, SST_DEV, SST_DEV_WIN
                .DW     SST_O_END, SST_DEVSTR_END, SST_DEV, SST_DEV_WIN
                .DW     0

; Ordinary strings
SST_O_ROM       .ASCII_W "<ROM>\nsecond line"
SST_O_END       .ASCII_W "last:<>"

; All combinations of the characters that LOG_STR and SCR$PRINTSTR treat as
; the start of a new line, and the same characters where they are no new line:
; A, backslash n, B, CR LF, C, CR n, D, backslash LF, E, CR x, F, backslash y,
; G. The assembler turns a backslash n into CR LF, so this needs to be data.
SST_O_DW        .DW     0x0041, 0x005C, 0x006E, 0x0042, 0x000D, 0x000A
                .DW     0x0043, 0x000D, 0x006E, 0x0044, 0x005C, 0x000A
                .DW     0x0045, 0x000D, 0x0078, 0x0046, 0x005C, 0x0079
                .DW     0x0047, 0x0000

; ----------------------------------------------------------------------------
; String ROM strings for the edge cases that do not depend on their position
; in the string ROM
; ----------------------------------------------------------------------------

;STRROM_BEGIN
SST_S_EMPTY     .ASCII_W ""
SST_S_ONE       .ASCII_W "x"
SST_S_UART      .ASCII_W "uart\n"
SST_S_LINES     .ASCII_W "first line\nsecond line\n"
SST_S_EMPTYLNS  .ASCII_W "\n\nafter two empty lines\n\nend"
SST_S_ANGLE     .ASCII_W "<dir> a<b>c <<>>"

; a single backslash that is not followed by an n
SST_S_BACKSL    .ASCII_P "lone back\s"
                .ASCII_W "lash"

; labels in the middle of a string
SST_S_MID1      .ASCII_P "one, "
SST_S_MID2      .ASCII_P "two, "
SST_S_MID3      .ASCII_W "three"

; a label on a line of its own and two labels for one string
SST_S_ALIAS1
SST_S_ALIAS2    .ASCII_W "two labels"

; all printable characters but the double quote and the backslash
SST_S_CHARS     .ASCII_P " !#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOP"
                .ASCII_W "QRSTUVWXYZ[]^_`abcdefghijklmnopqrstuvwxyz{|}~"

SST_S_SPACES    .ASCII_W "  two spaces around  "
SST_S_MARKER    .ASCII_W ";STRROM_END is no marker inside of a string"
;STRROM_END

; ----------------------------------------------------------------------------
; Case table
;
; One record per string and combination of device, window and cursor:
;
;    word 0: routines to call: SST_RT_* for job 0, shifted left by three bits
;            per job for the other jobs; 0xFFFF ends the table
;    word 1: R8: pointer or handle
;    word 2: device to select
;    word 3: 4k window to select
;    word 4: SCR$PRINTSTR: SCR$CUR_X
;    word 5: SCR$PRINTSTR: SCR$CUR_Y
;    word 6: SCR$PRINTSTR: SCR$ILX
;
; The table starts with the records for the ordinary strings. A string that
; is located in the 4k window needs its device and window to be selected.
; strrom_sim_fixtures.asm continues the table with the records for the
; handles and ends it.
; ----------------------------------------------------------------------------

                ; in ROM below and above the table of the string ROM
SST_CASES       .DW     SST_RT_ALL, IO$HEX_NIBBLES
                .DW     SST_DEV, SST_DEV_WIN, 0, 0, 0
                .DW     SST_RT_ALL, SST_O_ROM
                .DW     M2M$STRROM, 1, 3, 2, 1
                .DW     SST_RT_ALL, SST_O_DW
                .DW     M2M$VRAM_DATA, 0, 2, 3, 1

                ; real strings of the Shell that are no string ROM strings
                .DW     SST_RT_ALL, NEWLINE
                .DW     M2M$VRAM_ATTR, 0, 5, 5, 0
                .DW     SST_RT_ALL, ERR_F_ATRMLOAD
                .DW     M2M$SYS_INFO, M2M$SYS_VGA, 1, 1, 1

                ; in RAM
                .DW     SST_RT_ALL, SST_RAMSTR
                .DW     SST_DEV, SST_DEV_WIN, 0, 8, 2

                ; in the 4k window of a device of the core
                .DW     SST_RT_ALL, SST_DEVSTR
                .DW     SST_DEV, SST_DEV_WIN, 4, 1, 3
                .DW     SST_RT_ALL, SST_DEVSTR_END
                .DW     SST_DEV, SST_DEV_WIN, 0, 20, 0

                ; in the 4k window of config.vhd: OPTM_S_MOUNT from its start
                ; and from its second character, DIR_START
                .DW     SST_RT_ALL, M2M$RAMROM_DATA
                .DW     M2M$CONFIG, M2M$CFG_OPTM_MSTR, 1, 22, 1
                .DW     SST_RT_ALL, 0x7001
                .DW     M2M$CONFIG, M2M$CFG_OPTM_MSTR, 20, 22, 1
                .DW     SST_RT_ALL, M2M$RAMROM_DATA
                .DW     M2M$CONFIG, M2M$CFG_DIR_START, 0, 24, 0

#include "strrom_sim_fixtures.asm"

; ----------------------------------------------------------------------------
; Variables
; ----------------------------------------------------------------------------

                .ORG    0x8000

#include "../screen_vars.asm"

; variables of the Shell that ../tools.asm refers to
OPTM_ICOUNT     .BLOCK 1
SD_WAIT_DONE    .BLOCK 1
SD_CYC_MID      .BLOCK 1
SD_CYC_HI       .BLOCK 1

SST_V_JOB       .BLOCK 1                        ; number of the job
SST_V_SEC       .BLOCK 1                        ; sections of the job
SST_V_MPUTS     .BLOCK 1                        ; routine bits of the job
SST_V_MLOG      .BLOCK 1
SST_V_MSCR      .BLOCK 1
SST_V_PRE       .BLOCK 1                        ; next entry of SST_PRESETS
SST_V_VAL       .BLOCK 1                        ; value for SST$OPENCASE
SST_V_FLG       .BLOCK 1                        ; flags for SST$SETFLAGS
SST_V_PTR       .BLOCK 1                        ; current entry of SST_BOUND

                .ORG    0xFEE0

#include "../main_vars.asm"
