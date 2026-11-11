; ****************************************************************************
; MiSTer2MEGA65 (M2M) QNICE ROM
;
; Testbed for the 512-bit menu state register M2M$CFM_ADDR / M2M$CFM_DATA
;
; Unlike the other testbeds, this one does not run in the QNICE emulator
; (which has no M2M registers): cfm_test.py builds it as a self-contained
; RELEASE-style ROM (QNICE Monitor at 0x0000, exactly like m2m-rom.asm) and
; runs it on the real QNICE CPU inside the real M2M/vhdl/QNICE/qnice.vhd in
; a ghdl simulation (cfm_tb.vhd). The routines under test are copied verbatim
; from the Shell sources into cfm_test_extract.asm by cfm_test.py:
; M2M$GET_SETTING / M2M$SET_SETTING (tools.asm) and ROSM_REM_OLD /
; ROSM_CHANGES (options.asm).
;
; Result protocol: the testbed writes 0x600D (pass) or 0xBAD0 plus the number
; of the failing step into the first word of the M2M$CFD_DATA register and
; halts (0xBADF: FATAL was called). The
; testbench reads it from control_d_o and additionally checks the final
; 512-bit control_m_o vector (exactly the bits in CT_IDX are set).
;
; done by sy2002 in 2026 and licensed under GPL v3
; ****************************************************************************

#define RELEASE
#include "../main.asm"

                ; The register file of the simulated CPU starts undefined, so
                ; the idiom XOR Rx, Rx would yield X instead of 0 as on the
                ; hardware: clear R0..R7 of all 32 register banks of the M2M
                ; QNICE (SHADOW_REGFILE_SIZE in qnice_globals.vhd) from bank
                ; 31 down to bank 0, and R8..R12
START_FIRMWARE  MOVE    32, R8
_CT_RB          SUB     1, R8                   ; R8: bank 31 .. 0
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
                RBRA    _CT_RB, !Z
                MOVE    0, R9
                MOVE    0, R10
                MOVE    0, R11
                MOVE    0, R12

                MOVE    OPTM_ICOUNT, R0         ; a menu of the maximum size
                MOVE    512, @R0
                MOVE    CONFIG_FILE, R0         ; not null: ROSM_* are active
                MOVE    1, @R0
                MOVE    M2M$CFM_ADDR, R10       ; R10: bank selector
                MOVE    M2M$CFM_DATA, R11       ; R11: 16-bit window

                ; step 1: the bank selector stores 5 bits (0..31)
                MOVE    1, R12                  ; R12: current step
                MOVE    31, @R10
                CMP     31, @R10
                RBRA    CT_FAIL, !Z
                MOVE    32, @R10                ; bit 5 is not stored
                CMP     0, @R10
                RBRA    CT_FAIL, !Z

                ; step 2: all 32 banks are distinct registers: tag every bank
                ; with its number, then read all tags back (a 4-bit selector
                ; would alias bank 16..31 onto bank 0..15)
                MOVE    2, R12
                XOR     R1, R1
_CT_TAGW        MOVE    R1, @R10
                MOVE    R1, R2
                ADD     0xA500, R2
                MOVE    R2, @R11
                ADD     1, R1
                CMP     M2M$CFM_BANKS, R1
                RBRA    _CT_TAGW, !Z
                XOR     R1, R1
_CT_TAGR        MOVE    R1, @R10
                MOVE    R1, R2
                ADD     0xA500, R2
                CMP     R2, @R11
                RBRA    CT_FAIL, !Z
                ADD     1, R1
                CMP     M2M$CFM_BANKS, R1
                RBRA    _CT_TAGR, !Z

                ; step 3: clear all banks, then set the bits in CT_IDX via
                ; M2M$SET_SETTING
                MOVE    3, R12
                XOR     R1, R1
_CT_CLR         MOVE    R1, @R10
                MOVE    0, @R11
                ADD     1, R1
                CMP     M2M$CFM_BANKS, R1
                RBRA    _CT_CLR, !Z
                MOVE    CT_IDX, R1
_CT_SET         MOVE    @R1++, R8
                CMP     0xFFFF, R8
                RBRA    _CT_GET, Z
                MOVE    1, R9
                RSUB    M2M$SET_SETTING, 1
                RBRA    _CT_SET, 1

                ; step 4: M2M$GET_SETTING returns 1 exactly for the indices in
                ; CT_IDX, for all 512 menu items
_CT_GET         MOVE    4, R12
                XOR     R8, R8                  ; R8: menu item index
_CT_GET_1       RSUB    M2M$GET_SETTING, 1      ; R9: value of the setting
                XOR     R2, R2                  ; R2: expected value
                MOVE    CT_IDX, R1
_CT_GET_2       MOVE    @R1++, R3
                CMP     0xFFFF, R3
                RBRA    _CT_GET_3, Z
                CMP     R3, R8
                RBRA    _CT_GET_2, !Z
                MOVE    1, R2
_CT_GET_3       CMP     R2, R9
                RBRA    CT_FAIL, !Z
                ADD     1, R8
                CMP     512, R8
                RBRA    _CT_GET_1, !Z

                ; step 5: ROSM_REM_OLD copies all 32 banks into OLD_SETTINGS
                ; (shell_vars.asm), which must be large enough: INITIAL_SD is
                ; the variable right behind it and serves as a canary
                MOVE    5, R12
                MOVE    INITIAL_SD, R0
                MOVE    0x5A5A, @R0
                RSUB    ROSM_REM_OLD, 1
                CMP     0x5A5A, @R0
                RBRA    CT_FAIL, !Z

                ; step 6 to 10: ROSM_CHANGES compares all 32 banks with that
                ; copy: no change, then a change in the last bank (item 511)
                ; and in the first bank above the old 256-bit limit (item 256)
                MOVE    6, R12
                RSUB    ROSM_CHANGES, 1
                RBRA    CT_FAIL, C              ; nothing changed yet
                MOVE    7, R12
                MOVE    511, R8
                XOR     R9, R9
                RSUB    M2M$SET_SETTING, 1
                RSUB    ROSM_CHANGES, 1
                RBRA    CT_FAIL, !C             ; item 511 changed
                MOVE    8, R12
                MOVE    1, R9
                RSUB    M2M$SET_SETTING, 1
                RSUB    ROSM_CHANGES, 1
                RBRA    CT_FAIL, C              ; restored: no change
                MOVE    9, R12
                MOVE    256, R8
                XOR     R9, R9
                RSUB    M2M$SET_SETTING, 1
                RSUB    ROSM_CHANGES, 1
                RBRA    CT_FAIL, !C             ; item 256 changed
                MOVE    10, R12
                MOVE    1, R9
                RSUB    M2M$SET_SETTING, 1
                RSUB    ROSM_CHANGES, 1
                RBRA    CT_FAIL, C              ; restored: no change

                MOVE    0x600D, R0              ; all steps passed
                RBRA    CT_END, 1

CT_FAIL         MOVE    0xBAD0, R0              ; 0xBAD0 + failing step
                ADD     R12, R0
CT_END          MOVE    M2M$CFD_ADDR, R1
                MOVE    0, @R1
                MOVE    M2M$CFD_DATA, R1
                MOVE    R0, @R1
                HALT

; the routines under test need FATAL and their error strings
FATAL           MOVE    0xBADF, R0
                RBRA    CT_END, 1
ERR_FATAL_TG    .ASCII_W "M2M$GET_SETTING: Illegal index"
ERR_FATAL_TS    .ASCII_W "M2M$SET_SETTING: Illegal index"

; menu items that are set: the edges of the 16-bit windows around the old
; 256-bit limit and the very last item
CT_IDX          .DW     0, 15, 16, 255, 256, 300, 511, 0xFFFF

#include "cfm_test_extract.asm"

; ----------------------------------------------------------------------------
; Variables: the real ones of the Shell (OPTM_ICOUNT, CONFIG_FILE,
; OLD_SETTINGS, INITIAL_SD, ...)
; ----------------------------------------------------------------------------

                .ORG    0x8000

#include "../shell_vars.asm"

                .ORG    0xFEE0
#include "../main_vars.asm"
