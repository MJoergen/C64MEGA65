; ****************************************************************************
; C64MEGA65 physical internal-1581 OSM status helpers
;
; Pure state classification and fixed-width labels shared by the production
; firmware and the headless QNICE emulator test.
; ****************************************************************************

P1581_DIAG_DEV       .EQU 0x0108                ; C_DEV_C64_PHYS1581
P1581_RM_CTRL        .EQU 0x0004                ; RM_CTRL_STATE word offset
P1581_BUSY_MASK      .EQU 0xFC08                ; read | step | motor
P1581_RM_IMGBSY      .EQU 0x0028                ; RM_IMG_DRIVE word offset
P1581_IMGBSY_MSK     .EQU 0x0001                ; image drive busy or dirty

P1581_OS_IDLE        .EQU 0
P1581_OS_MOTOR       .EQU 1
P1581_OS_HEAD        .EQU 2
P1581_OS_READING     .EQU 3
P1581_OS_BUSY        .EQU 4                     ; defensive image-side activity
P1581_OS_INVALID     .EQU 0xFFFF

P1581_OSM_POLL_MASK  .EQU 0x0007                ; 763 Hz / 8 = about 95 Hz
P1581_OSM_LABEL_LEN  .EQU 23                    ; excludes selection marker

; Return a pointer to the first label word behind the selection marker of the
; internal-1581 menu line. The live OPTM_ITEMS heap copy uses literal backslash
; plus n as its line separator.
;
; Output: R8 = label pointer, or 0 if the copied menu string is malformed
P1581_OSM_LABEL_PTR
                INCRB
                MOVE    OPTM_DATA, R0
                MOVE    @R0, R0
                ADD     OPTM_IR_ITEMS, R0
                MOVE    @R0, R0
                MOVE    C64_OSM_INTERNAL_1581, R1
_P1581_LP_SEG   CMP     0, R1
                RBRA    _P1581_LP_FOUND, Z
_P1581_LP_CHAR  CMP     0, @R0
                RBRA    _P1581_LP_BAD, Z
                CMP     0x005C, @R0             ; backslash of the separator
                RBRA    _P1581_LP_NEXT, Z
                ADD     1, R0
                RBRA    _P1581_LP_CHAR, 1
_P1581_LP_NEXT  ADD     2, R0                   ; skip backslash and n
                SUB     1, R1
                RBRA    _P1581_LP_SEG, 1
_P1581_LP_FOUND ADD     1, R0                   ; skip selection-marker word
                MOVE    R0, R8
                RBRA    _P1581_LP_RET, 1
_P1581_LP_BAD   XOR     R8, R8
_P1581_LP_RET   DECRB
                RET

; Classify the two words used by the symmetric idle gate. Physical activity
; has priority so that the label explains what the internal mechanism does.
;
; Input:  R8 = RM_CTRL_STATE, R9 = RM_IMG_DRIVE
; Output: R8 = P1581_OS_* state, R9 unchanged
P1581_CLASSIFY INCRB
                MOVE    R8, R0
                AND     0xF000, R0              ; read FSM active?
                RBRA    _P1581_C_READ, !Z
                MOVE    R8, R0
                AND     0x0C00, R0              ; step FSM active?
                RBRA    _P1581_C_HEAD, !Z
                MOVE    R8, R0
                AND     0x0008, R0              ; motor on?
                RBRA    _P1581_C_MOTOR, !Z
                MOVE    R9, R0
                AND     P1581_IMGBSY_MSK, R0
                RBRA    _P1581_C_BUSY, !Z
                MOVE    P1581_OS_IDLE, R8
                RBRA    _P1581_C_RET, 1
_P1581_C_MOTOR MOVE    P1581_OS_MOTOR, R8
                RBRA    _P1581_C_RET, 1
_P1581_C_HEAD  MOVE    P1581_OS_HEAD, R8
                RBRA    _P1581_C_RET, 1
_P1581_C_READ  MOVE    P1581_OS_READING, R8
                RBRA    _P1581_C_RET, 1
_P1581_C_BUSY  MOVE    P1581_OS_BUSY, R8
_P1581_C_RET   DECRB
                RET

; Map a valid P1581_OS_* state to its zero-terminated, 23-character label.
;
; Input/Output: R8 = state / string pointer
P1581_STATUS_STR
                INCRB
                MOVE    P1581_OSM_STRINGS, R0
                ADD     R8, R0
                MOVE    @R0, R8
                DECRB
                RET

P1581_OSM_STRINGS
                .DW P1581_OSM_IDLE, P1581_OSM_MOTOR, P1581_OSM_HEAD
                .DW P1581_OSM_READING, P1581_OSM_BUSY

P1581_OSM_IDLE    .ASCII_W "Use internal 1581      "
P1581_OSM_MOTOR   .ASCII_W "Internal 1581 <Motor>  "
P1581_OSM_HEAD    .ASCII_W "Internal 1581 <Head>   "
P1581_OSM_READING .ASCII_W "Internal 1581 <Reading>"
P1581_OSM_BUSY    .ASCII_W "Internal 1581 <Busy>   "
