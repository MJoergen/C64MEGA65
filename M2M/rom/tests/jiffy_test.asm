; Emulator testbed for the JiffyDOS gate / status report (PREP_START) and the
; on-screen Kernal summary value (_SS_TRY_KERNAL). It mirrors the exact decision
; flow and string-assembly logic from CORE/m2m-rom/m2m-rom.asm (minus the
; framework MMIO M2M$GET/SET_SETTING and the _SS_APPEND_LABEL menu lookup, which
; is functionally a literal "JiffyDOS" copy) and drives every decision-table row.
; Run headless; a python checker asserts the exact stdout.

#include "../../QNICE/dist_kit/sysdef.asm"
#include "../../QNICE/dist_kit/monitor.def"

                .ORG 0x8000

; ----- test driver: walk the decision-table rows ----------------------------
START           MOVE    ROWS, R7                ; R7 -> table of (l0,l1,l2,...)
_TLOOP          MOVE    @R7, R8                 ; peek l0 (0xFFFF = end marker)
                CMP     0xFFFF, R8
                RBRA    _TEND, Z

                MOVE    SEP, R8                 ; row separator banner
                SYSCALL(puts, 1)

                MOVE    LDF, R0                 ; load this row into LDF[0..2]
                MOVE    @R7++, @R0
                ADD     1, R0
                MOVE    @R7++, @R0
                ADD     1, R0
                MOVE    @R7++, @R0

                RSUB    RPT, 1                  ; debug-console status report
                RSUB    SUMVAL, 1               ; on-screen Kernal summary value
                RBRA    _TLOOP, 1
_TEND           SYSCALL(exit, 1)

; (l0=jd-c64, l1=jd-c1541, l2=jd-c1581)
ROWS            .DW 0, 0, 0                     ; not-JiffyDOS rows are silent; we
                                               ; only feed JiffyDOS-selected rows
                .DW 1, 1, 1                     ; JD . JD . JD
                .DW 1, 1, 0                     ; JD . JD . STD
                .DW 1, 0, 1                     ; JD . STD . JD  (the new case)
                .DW 1, 0, 0                     ; revert (no drive ROM)
                .DW 0, 1, 1                     ; revert (no jd-c64)
                .DW 0xFFFF

; ===========================================================================
; verbatim copy of the PREP_START report+gate flow (sans SET_SETTING) and the
; _JD_RPT_LINE helper from CORE/m2m-rom/m2m-rom.asm
; ===========================================================================
RPT             INCRB
                MOVE    JDS_HEADER, R8
                SYSCALL(puts, 1)

                MOVE    LDF, R0
                MOVE    JDS_L_C64, R8
                MOVE    @R0, R9
                MOVE    JDS_F_C64, R10
                RSUB    _JD_RPT_LINE, 1
                CMP     0, @R0
                RBRA    _RPT_HAVE_C64, !Z
                MOVE    JDS_R_NOC64, R8
                RBRA    _RPT_REVERT, 1

_RPT_HAVE_C64   MOVE    LDF, R0
                ADD     1, R0
                MOVE    JDS_L_1541, R8
                MOVE    @R0, R9
                MOVE    JDS_F_1541, R10
                RSUB    _JD_RPT_LINE, 1
                MOVE    @R0, R1

                MOVE    LDF, R0
                ADD     2, R0
                MOVE    JDS_L_1581, R8
                MOVE    @R0, R9
                MOVE    JDS_F_1581, R10
                RSUB    _JD_RPT_LINE, 1
                ADD     @R0, R1

                CMP     0, R1
                RBRA    _RPT_NODRV, Z
                MOVE    JDS_V_ACTIVE, R8
                SYSCALL(puts, 1)
                RBRA    _RPT_RET, 1

_RPT_NODRV      MOVE    JDS_R_NODRV, R8
_RPT_REVERT     MOVE    R8, R0
                MOVE    JDS_V_DIS_PRE, R8
                SYSCALL(puts, 1)
                MOVE    R0, R8
                SYSCALL(puts, 1)
                MOVE    JDS_V_DIS_SUF, R8
                SYSCALL(puts, 1)
_RPT_RET        DECRB
                RET

_JD_RPT_LINE    INCRB
                MOVE    R9, R0
                MOVE    R10, R1
                SYSCALL(puts, 1)
                CMP     0, R0
                RBRA    _JD_RPT_STD, Z
                MOVE    JDS_V_JIFFY, R8
                SYSCALL(puts, 1)
                RBRA    _JD_RPT_RET, 1
_JD_RPT_STD     MOVE    JDS_STD_PRE, R8
                SYSCALL(puts, 1)
                MOVE    R1, R8
                SYSCALL(puts, 1)
                MOVE    JDS_STD_SUF, R8
                SYSCALL(puts, 1)
_JD_RPT_RET     DECRB
                RET

; ===========================================================================
; mirror of the _SS_TRY_KERNAL value build (literal "JiffyDOS" stands in for the
; _SS_APPEND_LABEL menu copy) + verbatim _SS_APPEND_STR
; ===========================================================================
SUMVAL          INCRB
                MOVE    LDF, R2
                MOVE    R2, R3
                ADD     1, R3
                MOVE    @R3, R3                 ; R3 = LDF[1]
                MOVE    R2, R4
                ADD     2, R4
                MOVE    @R4, R4                 ; R4 = LDF[2]

                ; gate the rendering exactly like the real callback: only when
                ; jd-c64 (LDF[0]) loaded; else fall back to the radio label
                CMP     0, @R2
                RBRA    _SV_EMPTY, Z

                MOVE    SS_VALUE, R8
                MOVE    SS_VALUE, R6
                ADD     SS_VALUE_LEN, R6
                SUB     1, R6

                CMP     0, R3
                RBRA    _SV_NB, Z
                CMP     0, R4
                RBRA    _SV_NB, Z
                MOVE    SS_K_BOTH, R9
                MOVE    R6, R10
                RSUB    _SS_APPEND_STR, 1
                RBRA    _SV_DONE, 1

_SV_NB          MOVE    R3, R5
                ADD     R4, R5
                CMP     0, R5
                RBRA    _SV_EMPTY, Z
                MOVE    SS_K_JIFFY, R9         ; stands in for _SS_APPEND_LABEL
                MOVE    R6, R10
                RSUB    _SS_APPEND_STR, 1
                MOVE    SS_KT_1581, R9
                CMP     0, R3
                RBRA    _SV_TAG, Z
                MOVE    SS_KT_1541, R9
_SV_TAG         MOVE    R6, R10
                RSUB    _SS_APPEND_STR, 1

_SV_DONE        MOVE    0, @R8
                MOVE    SUMPRE, R8             ; " Kernal: " (rendered prefix)
                SYSCALL(puts, 1)
                MOVE    SS_VALUE, R8
                SYSCALL(puts, 1)
                MOVE    NLSTR, R8
                SYSCALL(puts, 1)
                RBRA    _SV_RET, 1
_SV_EMPTY       MOVE    SUMDEF, R8
                SYSCALL(puts, 1)
_SV_RET         DECRB
                RET

_SS_APPEND_STR  INCRB
                MOVE    R8, R0
                MOVE    R9, R1
                MOVE    R10, R2
_SS_AS_COPY     CMP     R2, R0
                RBRA    _SS_AS_DONE, Z
                MOVE    @R1, R3
                CMP     0, R3
                RBRA    _SS_AS_DONE, Z
                MOVE    R3, @R0
                ADD     1, R0
                ADD     1, R1
                RBRA    _SS_AS_COPY, 1
_SS_AS_DONE     MOVE    R0, R8
                DECRB
                RET

; ----- strings (verbatim from m2m-rom.asm) ----------------------------------
JDS_HEADER      .ASCII_W "JiffyDOS status:\n"
JDS_L_C64       .ASCII_W "  C64 Kernal: "
JDS_L_1541      .ASCII_W "  1541 DOS  : "
JDS_L_1581      .ASCII_W "  1581 DOS  : "
JDS_V_JIFFY     .ASCII_W "JiffyDOS\n"
JDS_STD_PRE     .ASCII_W "standard (jd-"
JDS_STD_SUF     .ASCII_W ".bin not found)\n"
JDS_F_C64       .ASCII_W "c64"
JDS_F_1541      .ASCII_W "c1541"
JDS_F_1581      .ASCII_W "c1581"
JDS_V_ACTIVE    .ASCII_W "  -> JiffyDOS active\n"
JDS_V_DIS_PRE   .ASCII_W "  -> JiffyDOS disabled ("
JDS_R_NOC64     .ASCII_W "no JiffyDOS C64 Kernal"
JDS_R_NODRV     .ASCII_W "no drive ROM"
JDS_V_DIS_SUF   .ASCII_W "), using standard Kernal\n"

SS_K_BOTH       .ASCII_W "Jiffy 1541+1581"
SS_KT_1541      .ASCII_W " 1541"
SS_KT_1581      .ASCII_W " 1581"
SS_K_JIFFY      .ASCII_W "JiffyDOS"

; testbed-only decoration
SEP             .ASCII_W "== row ==\n"
SUMPRE          .ASCII_W " Kernal: "
SUMDEF          .ASCII_W " Kernal: (radio label)\n"
NLSTR           .ASCII_W "\n"

SS_VALUE_LEN    .EQU 24
SS_VALUE        .BLOCK 24
LDF             .BLOCK 3
