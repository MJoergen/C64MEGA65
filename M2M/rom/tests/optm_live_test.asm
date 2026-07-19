; ****************************************************************************
; MiSTer2MEGA65 (M2M) QNICE ROM
;
; Headless testbed for OPTM_LIVE_TEXT and the OPTM_FOREGROUND lifecycle.
; It drives the full OPTM_RUN loop and verifies fixed-width replacement,
; direct-paint coordinates, hidden lines, malformed input, selection callback
; suppression and closed-menu backing updates.
;
; Run the whole menu suite with:
;     python3 menu_test.py run
;
; done by sy2002 in 2026 and licensed under GPL v3
; ****************************************************************************

#include "../../QNICE/dist_kit/sysdef.asm"
#include "../../QNICE/dist_kit/monitor.def"

                .ORG    0x8000

                MOVE    LT_S_BEGIN, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)

                ; OPTM_LIVE_TEXT requires the same writable item copy that the
                ; production options setup places on its menu heap.
                MOVE    LT_ITEMS_DEF, R8
                MOVE    LT_ITEMS, R9
                MOVE    LT_ITEMS_LEN, R10
                SYSCALL(memcpy, 1)

                MOVE    LT_PHASE, R8
                MOVE    0, @R8
                MOVE    LT_PAINT_COUNT, R8
                MOVE    0, @R8

                MOVE    LT_REC, R8
                MOVE    3, R9                   ; frame x
                MOVE    4, R10                  ; frame y
                MOVE    30, R11
                MOVE    12, R12
                RSUB    OPTM_INIT, 1

                MOVE    OPTM_FOREGROUND, R8
                MOVE    @R8, R8
                MOVE    0, R9
                MOVE    LT_E_INIT_FG, R10
                RSUB    LT_CHECK_WORD, 1

                MOVE    1, R8                   ; start on visible test line
                RSUB    OPTM_RUN, 1

                ; OPTM_RUN must withdraw both public lifecycle indicators.
                MOVE    OPTM_FOREGROUND, R8
                MOVE    @R8, R8
                MOVE    0, R9
                MOVE    LT_E_CLOSED_FG, R10
                RSUB    LT_CHECK_WORD, 1
                MOVE    OPTM_STRUCT, R8
                MOVE    @R8, R8
                MOVE    0, R9
                MOVE    LT_E_CLOSED_ST, R10
                RSUB    LT_CHECK_WORD, 1

                ; A closed menu still receives the backing-text update but no
                ; direct paint. The next full show will use the new text.
                MOVE    LT_PAINT_COUNT, R8
                MOVE    0, @R8
                MOVE    1, R8
                MOVE    1, R9
                MOVE    LT_CLOSED, R10
                MOVE    6, R11
                RSUB    OPTM_LIVE_TEXT, 1

                MOVE    LT_ITEMS, R8
                ADD     LT_VISIBLE_OFF, R8
                MOVE    LT_CLOSED, R9
                MOVE    6, R10
                MOVE    LT_E_CLOSED_TXT, R11
                RSUB    LT_CHECK_STR, 1
                MOVE    LT_PAINT_COUNT, R8
                MOVE    @R8, R8
                MOVE    0, R9
                MOVE    LT_E_CLOSED_PAINT, R10
                RSUB    LT_CHECK_WORD, 1

                MOVE    LT_S_INACTIVE, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                MOVE    LT_S_DONE, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                SYSCALL(exit, 1)

; ----------------------------------------------------------------------------
; First key wait: test the live API while OPTM_RUN owns the main-menu surface.
; Second key wait: prove that ownership was restored after the callback.
; ----------------------------------------------------------------------------

LT_GETKEY       INCRB
                MOVE    LT_PHASE, R0
                CMP     0, @R0
                RBRA    _LT_GK_SECOND, !Z
                MOVE    1, @R0

                MOVE    OPTM_FOREGROUND, R8
                MOVE    @R8, R8
                MOVE    1, R9
                MOVE    LT_E_OPEN_FG, R10
                RSUB    LT_CHECK_WORD, 1
                MOVE    LT_PAINT_COUNT, R8
                MOVE    0, @R8

                ; Visible replacement: also verify all public input registers
                ; and the exact direct-paint call made through the init record.
                MOVE    1, R8
                MOVE    1, R9
                MOVE    LT_READY, R10
                MOVE    6, R11
                MOVE    0x4444, R4
                MOVE    0x7777, R7
                MOVE    0xCCCC, R12
                RSUB    OPTM_LIVE_TEXT, 1
                CMP     0x4444, R4
                RBRA    _LT_GK_REGFAIL, !Z
                CMP     0x7777, R7
                RBRA    _LT_GK_REGFAIL, !Z
                CMP     1, R8
                RBRA    _LT_GK_REGFAIL, !Z
                CMP     1, R9
                RBRA    _LT_GK_REGFAIL, !Z
                CMP     LT_READY, R10
                RBRA    _LT_GK_REGFAIL, !Z
                CMP     6, R11
                RBRA    _LT_GK_REGFAIL, !Z
                CMP     0xCCCC, R12
                RBRA    _LT_GK_REGFAIL, !Z

                MOVE    LT_ITEMS, R8
                ADD     LT_VISIBLE_OFF, R8
                MOVE    LT_READY, R9
                MOVE    6, R10
                MOVE    LT_E_VISIBLE_TXT, R11
                RSUB    LT_CHECK_STR, 1
                MOVE    LT_PAINT_COUNT, R8
                MOVE    @R8, R8
                MOVE    1, R9
                MOVE    LT_E_VISIBLE_CNT, R10
                RSUB    LT_CHECK_WORD, 1
                MOVE    LT_PAINT_PTR, R8
                MOVE    @R8, R8
                MOVE    LT_READY, R9
                MOVE    LT_E_VISIBLE_PTR, R10
                RSUB    LT_CHECK_WORD, 1
                MOVE    LT_PAINT_X, R8
                MOVE    @R8, R8
                MOVE    5, R9                   ; frame + border + offset
                MOVE    LT_E_VISIBLE_X, R10
                RSUB    LT_CHECK_WORD, 1
                MOVE    LT_PAINT_Y, R8
                MOVE    @R8, R8
                MOVE    6, R9                   ; frame + border + visible row
                MOVE    LT_E_VISIBLE_Y, R10
                RSUB    LT_CHECK_WORD, 1
                MOVE    LT_PAINT_LEVEL, R8
                MOVE    @R8, R8
                MOVE    0, R9
                MOVE    LT_E_VISIBLE_LVL, R10
                RSUB    LT_CHECK_WORD, 1

                MOVE    LT_S_VISIBLE, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)

                ; Invalid source length, out-of-range item and a replacement
                ; crossing a line boundary must all be harmless no-ops.
                MOVE    LT_PAINT_COUNT, R8
                MOVE    0, @R8
                MOVE    1, R8
                MOVE    1, R9
                MOVE    LT_SHORT, R10
                MOVE    6, R11
                RSUB    OPTM_LIVE_TEXT, 1
                MOVE    LT_ITEMS, R8
                ADD     LT_VISIBLE_OFF, R8
                MOVE    LT_READY, R9
                MOVE    6, R10
                MOVE    LT_E_SHORT_TXT, R11
                RSUB    LT_CHECK_STR, 1
                MOVE    99, R8
                MOVE    0, R9
                MOVE    LT_READY, R10
                MOVE    6, R11
                RSUB    OPTM_LIVE_TEXT, 1
                MOVE    1, R8
                MOVE    1, R9
                MOVE    0, R10
                MOVE    6, R11
                RSUB    OPTM_LIVE_TEXT, 1
                MOVE    LT_ITEMS, R8
                ADD     LT_VISIBLE_OFF, R8
                MOVE    LT_READY, R9
                MOVE    6, R10
                MOVE    LT_E_INDEX_TXT, R11
                RSUB    LT_CHECK_STR, 1
                MOVE    1, R8
                MOVE    5, R9
                MOVE    LT_READY, R10
                MOVE    6, R11
                RSUB    OPTM_LIVE_TEXT, 1
                MOVE    LT_ITEMS, R8
                ADD     LT_VISIBLE_OFF, R8
                MOVE    LT_READY, R9
                MOVE    6, R10
                MOVE    LT_E_INVALID_TXT, R11
                RSUB    LT_CHECK_STR, 1
                MOVE    LT_PAINT_COUNT, R8
                MOVE    @R8, R8
                MOVE    0, R9
                MOVE    LT_E_INVALID_PAINT, R10
                RSUB    LT_CHECK_WORD, 1

                MOVE    LT_S_INVALID, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)

                ; A line inside the submenu is updated in backing memory but
                ; is not painted while the main menu is active.
                MOVE    3, R8
                MOVE    1, R9
                MOVE    LT_HIDDEN, R10
                MOVE    8, R11
                RSUB    OPTM_LIVE_TEXT, 1
                MOVE    LT_ITEMS, R8
                ADD     LT_HIDDEN_OFF, R8
                MOVE    LT_HIDDEN, R9
                MOVE    8, R10
                MOVE    LT_E_HIDDEN_TXT, R11
                RSUB    LT_CHECK_STR, 1
                MOVE    LT_PAINT_COUNT, R8
                MOVE    @R8, R8
                MOVE    0, R9
                MOVE    LT_E_HIDDEN_PAINT, R10
                RSUB    LT_CHECK_WORD, 1

                MOVE    LT_S_HIDDEN, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                MOVE    OPTM_KEY_SELECT, R8
                DECRB
                RET

_LT_GK_REGFAIL MOVE    LT_E_REGS, R8
                DECRB
                RBRA    LT_FAIL, 1

_LT_GK_SECOND  MOVE    OPTM_FOREGROUND, R8
                MOVE    @R8, R8
                MOVE    1, R9
                MOVE    LT_E_RESTORE_FG, R10
                RSUB    LT_CHECK_WORD, 1
                MOVE    LT_ITEMS, R8
                ADD     LT_VISIBLE_OFF, R8
                MOVE    LT_CALLBK, R9
                MOVE    6, R10
                MOVE    LT_E_CALLBK_TXT, R11
                RSUB    LT_CHECK_STR, 1
                MOVE    LT_PAINT_COUNT, R8
                MOVE    @R8, R8
                MOVE    0, R9
                MOVE    LT_E_CALLBK_PAINT, R10
                RSUB    LT_CHECK_WORD, 1

                MOVE    LT_S_FOREGROUND, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                MOVE    OPTM_KEY_CLOSE, R8
                DECRB
                RET

; ----------------------------------------------------------------------------
; The menu selection callback runs with foreground ownership withdrawn.
; ----------------------------------------------------------------------------

LT_CB_SEL       INCRB
                MOVE    R8, R4
                MOVE    R9, R5
                MOVE    R10, R6

                MOVE    OPTM_FOREGROUND, R8
                MOVE    @R8, R8
                MOVE    0, R9
                MOVE    LT_E_CALLBK_FG, R10
                RSUB    LT_CHECK_WORD, 1
                MOVE    LT_PAINT_COUNT, R8
                MOVE    0, @R8

                MOVE    1, R8
                MOVE    1, R9
                MOVE    LT_CALLBK, R10
                MOVE    6, R11
                RSUB    OPTM_LIVE_TEXT, 1
                MOVE    LT_ITEMS, R8
                ADD     LT_VISIBLE_OFF, R8
                MOVE    LT_CALLBK, R9
                MOVE    6, R10
                MOVE    LT_E_CALLBK_TXT, R11
                RSUB    LT_CHECK_STR, 1
                MOVE    LT_PAINT_COUNT, R8
                MOVE    @R8, R8
                MOVE    0, R9
                MOVE    LT_E_CALLBK_PAINT, R10
                RSUB    LT_CHECK_WORD, 1

                MOVE    LT_S_CALLBACK, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                MOVE    R4, R8
                MOVE    R5, R9
                MOVE    R6, R10
                DECRB
                RET

; ----------------------------------------------------------------------------
; Callback spies, checks and failure path
; ----------------------------------------------------------------------------

LT_PRINTXY      INCRB
                MOVE    LT_PAINT_COUNT, R0
                ADD     1, @R0
                MOVE    LT_PAINT_PTR, R0
                MOVE    R8, @R0
                MOVE    LT_PAINT_X, R0
                MOVE    R9, @R0
                MOVE    LT_PAINT_Y, R0
                MOVE    R10, @R0
                MOVE    LT_PAINT_LEVEL, R0
                MOVE    R11, @R0
                DECRB
                RET

LT_STUB         RET

LT_FATAL        MOVE    LT_E_FATAL, R8
                RBRA    LT_FAIL, 1

; R8 actual, R9 expected, R10 failure text
LT_CHECK_WORD   CMP     R9, R8
                RBRA    _LT_CW_RET, Z
                MOVE    R10, R8
                RBRA    LT_FAIL, 1
_LT_CW_RET      RET

; R8 actual pointer, R9 expected pointer, R10 character count, R11 failure text
LT_CHECK_STR    INCRB
                MOVE    R8, R0
                MOVE    R9, R1
                MOVE    R10, R2
_LT_CS_LOOP     MOVE    @R0++, R3
                CMP     @R1++, R3
                RBRA    _LT_CS_BAD, !Z
                SUB     1, R2
                RBRA    _LT_CS_LOOP, !Z
                DECRB
                RET
_LT_CS_BAD      MOVE    R11, R8
                DECRB
                RBRA    LT_FAIL, 1

LT_FAIL         MOVE    R8, R0
                MOVE    LT_S_FAIL, R8
                SYSCALL(puts, 1)
                MOVE    R0, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                SYSCALL(exit, 1)

; ----------------------------------------------------------------------------
; Initialization record and immutable test data
; ----------------------------------------------------------------------------

LT_REC          .DW     LT_STUB, LT_STUB, LT_STUB, LT_PRINTXY
                .DW     LT_STUB, LT_STUB, LT_GETKEY
                .DW     LT_CB_SEL, 0, LT_FATAL
                .DW     0x0078, 0, 0x0078, 0
                .DW     6, LT_ITEMS, LT_GROUPS, LT_STDSEL, LT_LINES, 0

LT_GROUPS       .DW     0x1000, 0x8001, 0x4000
                .DW     0x0002, 0x40FF, 0x00FF
LT_STDSEL       .DW     0, 0, 0, 0, 0, 0
LT_LINES        .DW     0, 0, 0, 0, 0, 0

LT_ITEMS_DEF    .ASCII_P " Title"
                .DW     0x005C, 0x006E
                .ASCII_P " old   "
                .DW     0x005C, 0x006E
                .ASCII_P " Sub"
                .DW     0x005C, 0x006E
                .ASCII_P " hidden  "
                .DW     0x005C, 0x006E
                .ASCII_P " Back"
                .DW     0x005C, 0x006E
                .ASCII_W " Close"

LT_ITEMS_LEN    .EQU 48
LT_VISIBLE_OFF  .EQU 9
LT_HIDDEN_OFF   .EQU 24

LT_READY        .ASCII_W "READY "
LT_SHORT        .ASCII_W "BAD"
LT_HIDDEN       .ASCII_W "HIDDEN  "
LT_CALLBK       .ASCII_W "CALLBK"
LT_CLOSED       .ASCII_W "CLOSED"

LT_S_BEGIN      .ASCII_W "== BEGIN =="
LT_S_VISIBLE    .ASCII_W "VISIBLE OK"
LT_S_INVALID    .ASCII_W "INVALID OK"
LT_S_HIDDEN     .ASCII_W "HIDDEN OK"
LT_S_CALLBACK   .ASCII_W "CALLBACK OK"
LT_S_FOREGROUND .ASCII_W "FOREGROUND OK"
LT_S_INACTIVE   .ASCII_W "INACTIVE OK"
LT_S_DONE       .ASCII_W "DONE"
LT_S_FAIL       .ASCII_W "FAIL: "

LT_E_INIT_FG       .ASCII_W "foreground set during init"
LT_E_OPEN_FG       .ASCII_W "foreground clear in key loop"
LT_E_REGS          .ASCII_W "input registers changed"
LT_E_VISIBLE_TXT   .ASCII_W "visible backing text"
LT_E_VISIBLE_CNT   .ASCII_W "visible paint count"
LT_E_VISIBLE_PTR   .ASCII_W "visible paint pointer"
LT_E_VISIBLE_X     .ASCII_W "visible paint x"
LT_E_VISIBLE_Y     .ASCII_W "visible paint y"
LT_E_VISIBLE_LVL   .ASCII_W "visible paint level"
LT_E_SHORT_TXT     .ASCII_W "short source changed text"
LT_E_INDEX_TXT     .ASCII_W "bad index changed text"
LT_E_INVALID_TXT   .ASCII_W "invalid update changed text"
LT_E_INVALID_PAINT .ASCII_W "invalid update painted"
LT_E_HIDDEN_TXT    .ASCII_W "hidden backing text"
LT_E_HIDDEN_PAINT  .ASCII_W "hidden update painted"
LT_E_CALLBK_FG     .ASCII_W "foreground set in callback"
LT_E_CALLBK_TXT    .ASCII_W "callback backing text"
LT_E_CALLBK_PAINT  .ASCII_W "callback update painted"
LT_E_RESTORE_FG    .ASCII_W "foreground not restored"
LT_E_CLOSED_FG     .ASCII_W "foreground set after run"
LT_E_CLOSED_ST     .ASCII_W "structure set after run"
LT_E_CLOSED_TXT    .ASCII_W "closed backing text"
LT_E_CLOSED_PAINT  .ASCII_W "closed update painted"
LT_E_FATAL         .ASCII_W "fatal callback"

; The component under test
#include "../menu.asm"
#include "../menu_vars.asm"

LT_PHASE        .BLOCK 1
LT_PAINT_COUNT  .BLOCK 1
LT_PAINT_PTR    .BLOCK 1
LT_PAINT_X      .BLOCK 1
LT_PAINT_Y      .BLOCK 1
LT_PAINT_LEVEL  .BLOCK 1
LT_ITEMS        .BLOCK LT_ITEMS_LEN
