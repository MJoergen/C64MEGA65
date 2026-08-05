; ****************************************************************************
; MiSTer2MEGA65 (M2M) QNICE ROM
;
; Testbed for the write-cache check of ROSM_SAVE (options.asm)
;
; ROSM_SAVE iterates over all virtual drives and checks whether any write
; cache is still dirty before it saves the on-screen-menu settings to the SD
; card. VD_DRV_READ returns its result in R8, which is the very register that
; carries the virtual drive number into the function. Using R8 as the loop
; counter therefore makes the loop spin forever as soon as there are two or
; more virtual drives with a clean write cache: upstream M2M issue #58.
;
; This testbed replays the loop against a stub of VD_DRV_READ that reproduces
; the destructive R8 behavior of the real function. Two variants are built
; from this one source, selected by TESTMODE on the qasm command line:
;
;    TESTMODE=0   the fixed loop as it is in options.asm today
;    TESTMODE=1   the loop as it was before the fix (expected to hang)
;
; The companion script rosm_save_test.py builds and runs both and checks that
; the fixed loop terminates for every drive count while the old one hangs.
;
; done by sy2002 in August 2026 and licensed under GPL v3
; ****************************************************************************

#include "../../QNICE/dist_kit/sysdef.asm"
#include "../../QNICE/dist_kit/monitor.def"

#ifndef TESTMODE
#define TESTMODE 0
#endif

; Register number that the real VD_DRV_READ would be asked for; same value as
; in sysdef.asm. The stub ignores it, it is only here to keep the call
; sequence identical to the original.
VD_CACHE_DIRTY  .EQU 0x700C

                .ORG    0x8000

                MOVE    STR_TITLE, R8
                SYSCALL(puts, 1)
#if TESTMODE == 1
                MOVE    STR_MODE_OLD, R8
#else
                MOVE    STR_MODE_NEW, R8
#endif
                SYSCALL(puts, 1)

; ----------------------------------------------------------------------------
; Phase A: every write cache clean, drive counts 1 to 15
; Expected: every drive count reports SAVE, i.e. the loop terminates
; ----------------------------------------------------------------------------

                RSUB    CLEAN_ALL, 1
                MOVE    1, R8
                MOVE    DRV_COUNT, R9
                MOVE    R8, @R9

_PHASE_A        MOVE    STR_A, R8
                SYSCALL(puts, 1)
                MOVE    DRV_COUNT, R8
                MOVE    @R8, R8
                SYSCALL(puthex, 1)
                MOVE    STR_ARROW, R8
                SYSCALL(puts, 1)
                RSUB    CACHE_CHECK, 1          ; C=1: save, C=0: do not save
                RSUB    PRINT_RESULT, 1
                MOVE    DRV_COUNT, R9
                ADD     1, @R9
                MOVE    @R9, R8
                CMP     16, R8
                RBRA    _PHASE_A, !Z

; ----------------------------------------------------------------------------
; Phase B: two drives, the second one dirty
; Expected: NOSAVE, i.e. the dirty cache is detected
; ----------------------------------------------------------------------------

                RSUB    CLEAN_ALL, 1
                MOVE    DIRTY_TBL, R0
                ADD     1, R0
                MOVE    1, @R0
                MOVE    DRV_COUNT, R9
                MOVE    2, @R9
                MOVE    STR_B, R8
                SYSCALL(puts, 1)
                RSUB    CACHE_CHECK, 1
                RSUB    PRINT_RESULT, 1

; ----------------------------------------------------------------------------
; Phase C: two drives, the first one dirty
; Expected: NOSAVE
; ----------------------------------------------------------------------------

                RSUB    CLEAN_ALL, 1
                MOVE    DIRTY_TBL, R0
                MOVE    1, @R0
                MOVE    DRV_COUNT, R9
                MOVE    2, @R9
                MOVE    STR_C, R8
                SYSCALL(puts, 1)
                RSUB    CACHE_CHECK, 1
                RSUB    PRINT_RESULT, 1

                MOVE    STR_DONE, R8
                SYSCALL(puts, 1)
                SYSCALL(exit, 1)

; ----------------------------------------------------------------------------
; The write-cache check of ROSM_SAVE
;
; Input:  DRV_COUNT: amount of virtual drives, as returned by VD_ACTIVE
;         DIRTY_TBL: one dirty flag per virtual drive
; Output: Carry=1: settings may be saved, Carry=0: do not save
; ----------------------------------------------------------------------------

CACHE_CHECK     INCRB

                MOVE    DRV_COUNT, R8
                MOVE    @R8, R8                 ; R8: amount of vdrives, this
                                                ; is what VD_ACTIVE returns

#if TESTMODE == 1
                ; The loop before the fix: R8 is both the loop counter and the
                ; register that VD_DRV_READ overwrites with its result
                MOVE    R8, R0                  ; R0: amount of vdrives
                XOR     R8, R8                  ; vdrive id
_CC_0           MOVE    VD_CACHE_DIRTY, R9
                RSUB    VD_DRV_READ, 1          ; get dirty flag for curr. drv
                CMP     0, R8                   ; dirty?
                RBRA    _CC_NOWR, !Z            ; yes: do not save
                ADD     1, R8                   ; no: check next vdrive
                CMP     R0, R8                  ; done?
                RBRA    _CC_0, !Z               ; no: next iteration
                RBRA    _CC_OK, 1               ; yes: detect changes and save
#else
                ; The loop as it is in options.asm today: the vdrive id lives
                ; in R1 and is copied to R8 before each call
                MOVE    R8, R0                  ; R0: amount of vdrives
                XOR     R1, R1                  ; R1: vdrive id
_CC_0           MOVE    R1, R8                  ; R8: vdrive id of curr. drv
                MOVE    VD_CACHE_DIRTY, R9
                RSUB    VD_DRV_READ, 1          ; get dirty flag for curr. drv
                CMP     0, R8                   ; dirty?
                RBRA    _CC_NOWR, !Z            ; yes: do not save
                ADD     1, R1                   ; no: check next vdrive
                CMP     R0, R1                  ; done?
                RBRA    _CC_0, !Z               ; no: next iteration
                RBRA    _CC_OK, 1               ; yes: detect changes and save
#endif

_CC_NOWR        AND     0xFFFB, SR              ; clear Carry: do not save
                DECRB
                RET

_CC_OK          OR      0x0004, SR              ; set Carry: save
                DECRB
                RET

; ----------------------------------------------------------------------------
; Stub of VD_DRV_READ that mimics the destructive R8 behavior of the original
;
; Input:  R8: Virtual drive number
;         R9: Register number (ignored by the stub)
; Output: R8: Value
; ----------------------------------------------------------------------------

VD_DRV_READ     INCRB

                MOVE    DIRTY_TBL, R0
                ADD     R8, R0
                MOVE    @R0, R8

                DECRB
                RET

; ----------------------------------------------------------------------------
; Helpers
; ----------------------------------------------------------------------------

CLEAN_ALL       INCRB
                MOVE    DIRTY_TBL, R0
                MOVE    16, R1
_CA_1           MOVE    0, @R0++
                SUB     1, R1
                RBRA    _CA_1, !Z
                DECRB
                RET

PRINT_RESULT    INCRB
                RBRA    _PR_OK, C
                MOVE    STR_NOSAVE, R8
                RBRA    _PR_OUT, 1
_PR_OK          MOVE    STR_SAVE, R8
_PR_OUT         SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                DECRB
                RET

; ----------------------------------------------------------------------------
; Variables and strings
; ----------------------------------------------------------------------------

DRV_COUNT       .BLOCK 1
DIRTY_TBL       .BLOCK 16

STR_TITLE       .ASCII_P "ROSM_SAVE write-cache check testbed\n"
                .ASCII_W "===================================\n\n"
STR_MODE_NEW    .ASCII_W "MODE: fixed loop (options.asm as of today)\n\n"
STR_MODE_OLD    .ASCII_W "MODE: old loop (before upstream M2M issue #58)\n\n"
STR_A           .ASCII_W "A clean drives=0x"
STR_ARROW       .ASCII_W " -> "
STR_B           .ASCII_W "B drives=0x2 drive 1 dirty -> "
STR_C           .ASCII_W "C drives=0x2 drive 0 dirty -> "
STR_SAVE        .ASCII_W "SAVE"
STR_NOSAVE      .ASCII_W "NOSAVE"
STR_DONE        .ASCII_W "\nDONE\n"
