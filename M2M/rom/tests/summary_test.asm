; ****************************************************************************
; Testbed for the custom SUBMENU_SUMMARY callback of the C64 core
; (CORE/m2m-rom/m2m-rom.asm): "Model: %s", "Kernal: %s" and "Volume: %s"
;
; Driven by summary_test.py, which copies the real callback (plus M2M$RPL_S
; and the summary data) into summary_test_gen.asm together with the menu
; fixtures and the test cases, and compares the output with its own model.
;
; Per case: reset the selected-state array to the menu defaults, apply the
; case differences and JiffyDOS load flags, call SUBMENU_SUMMARY for the
; opener of the case and print one line:
;
;   C <custom line or DEFAULT> | REGS OK
;
; REGS OK means: R9 and R10 unchanged (the documented contract) and the
; register bank of the caller (R0..R7) intact.
;
; done by sy2002 in 2026 and licensed under GPL v3
; ****************************************************************************

#include "../../QNICE/dist_kit/sysdef.asm"
#include "../../QNICE/dist_kit/monitor.def"

                .ORG    0x8000

                ; the masked groups array into the M2M$RAMROM window
                MOVE    ST_GROUPS, R8
                MOVE    M2M$RAMROM_DATA, R9
                MOVE    ST_N, R10
                SYSCALL(memcpy, 1)

                ; stub init record at HEAP: selected-state array and items
                MOVE    HEAP, R0
                ADD     OPTM_IR_STDSEL, R0
                MOVE    ST_STDSEL, @R0
                MOVE    HEAP, R0
                ADD     OPTM_IR_ITEMS, R0
                MOVE    ST_ITEMS, @R0

                ; OSM width including the frame, like SEL_OPTM_DIMENSIONS
                MOVE    SCR$OSM_O_DX, R0
                MOVE    ST_OSM_DX, @R0

                ; no init record for OPTM_DEP_OK: every line counts as visible
                ; (no volume, stereo or SID line carries a dependency)
                MOVE    OPTM_DATA, R0
                MOVE    0, @R0

                MOVE    ST_CUR, R0
                MOVE    ST_CASES, @R0

_ST_LOOP        MOVE    ST_CUR, R0
                MOVE    @R0, R4                 ; R4: case cursor
                CMP     0xFFFF, @R4             ; end of the case list?
                RBRA    _ST_DONE, Z

                MOVE    ST_BASE, R8             ; menu defaults
                MOVE    ST_STDSEL, R9
                MOVE    ST_N, R10
                SYSCALL(memcpy, 1)

                MOVE    @R4++, R5               ; R5: flat index of the opener
                MOVE    @R4++, R6               ; R6: opener string with %s
                MOVE    CRTROM_AUT_LDF, R7      ; JiffyDOS load flags
                MOVE    @R4++, @R7++
                MOVE    @R4++, @R7++
                MOVE    @R4++, @R7++
_ST_DIFF        MOVE    @R4++, R1               ; (index, value) pairs
                CMP     0xFFFF, R1
                RBRA    _ST_CALL, Z
                MOVE    @R4++, R2
                ADD     ST_STDSEL, R1
                MOVE    R2, @R1
                RBRA    _ST_DIFF, 1

_ST_CALL        MOVE    ST_CUR, R0              ; next case
                MOVE    R4, @R0

                MOVE    R6, R8                  ; R8: string with %s
                MOVE    M2M$RAMROM_DATA, R9     ; R9: ptr to the group word
                ADD     R5, R9
                MOVE    M2M$RAMROM_DATA, R10    ; R10: end-of-menu marker
                ADD     ST_N, R10
                MOVE    ST_R9, R0
                MOVE    R9, @R0
                MOVE    ST_R10, R0
                MOVE    R10, @R0

                MOVE    0x1111, R0              ; caller bank sentinels
                MOVE    0x2222, R1
                MOVE    0x3333, R2
                MOVE    0x4444, R3
                MOVE    0x5555, R4
                MOVE    0x6666, R5
                MOVE    0x7777, R6
                MOVE    0x8888, R7

                RSUB    SUBMENU_SUMMARY, 1

                MOVE    ST_RES, R11             ; keep the result
                MOVE    R8, @R11
                MOVE    ST_OK, R11              ; R11: verdict, 1 = OK
                MOVE    1, @R11
                MOVE    ST_R9, R12
                CMP     @R12, R9
                RBRA    _ST_BAD, !Z
                MOVE    ST_R10, R12
                CMP     @R12, R10
                RBRA    _ST_BAD, !Z
                CMP     0x1111, R0
                RBRA    _ST_BAD, !Z
                CMP     0x2222, R1
                RBRA    _ST_BAD, !Z
                CMP     0x3333, R2
                RBRA    _ST_BAD, !Z
                CMP     0x4444, R3
                RBRA    _ST_BAD, !Z
                CMP     0x5555, R4
                RBRA    _ST_BAD, !Z
                CMP     0x6666, R5
                RBRA    _ST_BAD, !Z
                CMP     0x7777, R6
                RBRA    _ST_BAD, !Z
                CMP     0x8888, R7
                RBRA    _ST_PRINT, Z
_ST_BAD         MOVE    ST_OK, R11
                MOVE    0, @R11

_ST_PRINT       MOVE    ST_S_C, R8
                SYSCALL(puts, 1)
                MOVE    ST_RES, R8
                MOVE    @R8, R8
                CMP     0, R8
                RBRA    _ST_PR_LINE, !Z
                MOVE    ST_S_DEF, R8
_ST_PR_LINE     SYSCALL(puts, 1)
                MOVE    ST_S_OK, R8
                MOVE    ST_OK, R9
                CMP     0, @R9
                RBRA    _ST_PR_V, !Z
                MOVE    ST_S_BAD, R8
_ST_PR_V        SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                RBRA    _ST_LOOP, 1

_ST_DONE        MOVE    ST_S_DONE, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                SYSCALL(exit, 1)

; the fatal path of M2M$RPL_S (no %s in the string) ends the run
FATAL           MOVE    ST_S_FATAL, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                SYSCALL(exit, 1)

ST_S_C          .ASCII_W "C "
ST_S_DEF        .ASCII_W "DEFAULT"
ST_S_OK         .ASCII_W " | REGS OK"
ST_S_BAD        .ASCII_W " | REGS BAD"
ST_S_DONE       .ASCII_W "DONE"
ST_S_FATAL      .ASCII_W "FATAL"

ST_CUR          .BLOCK  1
ST_R9           .BLOCK  1
ST_R10          .BLOCK  1
ST_RES          .BLOCK  1
ST_OK           .BLOCK  1

; the real menu code (OPTM_SUMM_SCAN, OPTM_NL, the init-record offsets)
#include "../menu.asm"
#include "../menu_vars.asm"

; generated: constants, the copied callback, fixtures and cases
#include "summary_test_gen.asm"
