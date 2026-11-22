; ****************************************************************************
; MiSTer2MEGA65 (M2M) QNICE ROM
;
; Keyboard controller (expects low-active keys in the QNICE register)
;
; The basic idea is: A key first has to be released until it can be counted
; as pressed again.
;
; The cursor keys repeat while they are held (typematic repeat): the first
; repeat comes M2M$TYPEMATIC_DLY after the key was pressed, then one every
; M2M$TYPEMATIC_SPD. Both are times, measured with the cycle counter
; (IO$CYC_MID, see sysdef.asm), so the repeat is equally fast no matter how
; much work the loop that calls KEYB$SCAN does in between.
;
; originally made for gbc4mega65 by sy2002 in 2021
; adpoted for MiSTer2MEGA65 by sy2002 in 2021 and licensed under GPL v3
; ****************************************************************************

; call this before working with this library
KEYB$INIT       INCRB
                MOVE    KEYB_PRESSED, R0
                MOVE    0xFFFF, @R0             ; low active, i.e. no keys
                MOVE    KEYB_NEWKEYS, R0
                MOVE    0, @R0                  ; high active, i.e. no keys
                MOVE    KEYB_CDN_TIME, R0       ; clear the typematic vars.
                MOVE    KEYB_TYPEM_WORDS, R1
_KEYB_INIT_LOOP MOVE    0, @R0++
                SUB     1, R1
                RBRA    _KEYB_INIT_LOOP, !Z
                MOVE    IO$CYC_STATE, R0        ; the typematic repeat needs..
                OR      CYC$RUN, @R0            ; ..the cycle counter running
                DECRB
                RET

; perform one scan iteration; meant to be called repeatedly
KEYB$SCAN       INCRB
                MOVE    R8, R0
                MOVE    R9, R1
                MOVE    R10, R2
                MOVE    R12, R3
                INCRB

                MOVE    M2M$KEYBOARD, R0        ; R0: keyboard status
                MOVE    @R0, R0
                NOT     R0, R0                  ; convert to high-active

                MOVE    KEYB_PRESSED, R1        ; R1 points to PRESSED
                MOVE    KEYB_NEWKEYS, R2        ; R2 points to NEWKEYS

                ; keys need to be released first to count as new keys again
                NOT     @R1, R3
                AND     R0, R3
                OR      R3, @R2

                ; store currently pressed keys
                MOVE    R0, @R1

                ; typematic repeat for the four cursor keys (only inside
                ; QNICE as Game Boy does its own thing): _KEYB_TYPEMATIC
                ; handles a pressed key; a key that is not pressed only needs
                ; its state cleared, which is done inline, so that a scan
                ; without cursor keys stays cheap
                MOVE    R1, R9                  ; R9: pointer to PRESSED
                MOVE    IO$CYC_MID, R12         ; R12: the time now
                MOVE    @R12, R12

                MOVE    R0, R4                  ; cursor down
                AND     M2M$KEY_DOWN, R4
                RBRA    _KEYB_SCAN_DN0, Z
                MOVE    M2M$KEY_DOWN, R8
                MOVE    KEYB_CDN_TIME, R10
                RSUB    _KEYB_TYPEMATIC, 1
                RBRA    _KEYB_SCAN_UP, 1
_KEYB_SCAN_DN0  MOVE    KEYB_CDN_STATE, R4      ; not pressed: clear state
                MOVE    0, @R4

_KEYB_SCAN_UP   MOVE    R0, R4                  ; cursor up
                AND     M2M$KEY_UP, R4
                RBRA    _KEYB_SCAN_UP0, Z
                MOVE    M2M$KEY_UP, R8
                MOVE    KEYB_CUP_TIME, R10
                RSUB    _KEYB_TYPEMATIC, 1
                RBRA    _KEYB_SCAN_LF, 1
_KEYB_SCAN_UP0  MOVE    KEYB_CUP_STATE, R4
                MOVE    0, @R4

_KEYB_SCAN_LF   MOVE    R0, R4                  ; cursor left
                AND     M2M$KEY_LEFT, R4
                RBRA    _KEYB_SCAN_LF0, Z
                MOVE    M2M$KEY_LEFT, R8
                MOVE    KEYB_CLF_TIME, R10
                RSUB    _KEYB_TYPEMATIC, 1
                RBRA    _KEYB_SCAN_RT, 1
_KEYB_SCAN_LF0  MOVE    KEYB_CLF_STATE, R4
                MOVE    0, @R4

_KEYB_SCAN_RT   MOVE    R0, R4                  ; cursor right
                AND     M2M$KEY_RIGHT, R4
                RBRA    _KEYB_SCAN_RT0, Z
                MOVE    M2M$KEY_RIGHT, R8
                MOVE    KEYB_CRT_TIME, R10
                RSUB    _KEYB_TYPEMATIC, 1
                RBRA    _KEYB_SCAN_END, 1
_KEYB_SCAN_RT0  MOVE    KEYB_CRT_STATE, R4
                MOVE    0, @R4

_KEYB_SCAN_END  DECRB
                MOVE    R0, R8
                MOVE    R1, R9
                MOVE    R2, R10
                MOVE    R3, R12
                DECRB
                RET

; returns new key in R8
KEYB$GETKEY     INCRB

                MOVE    1, R0                   ; R0: key scanner
                MOVE    KEYB_NEWKEYS, R1        ; R1: list of new keys

_KEYB_GK_LOOP   MOVE    @R1, R2                 ; scan at current R0 pos.
                AND     R0, R2
                RBRA    _KEYBGK_RET_R2, !Z      ; key found? return it
                AND     0xFFFD, SR              ; no: clear X-flag, shift in 0
                SHL     1, R0                   ; move "scanner"
                RBRA    _KEYB_GK_LOOP, !Z       ; loop if not yet done
                RBRA    _KEYBGK_RET_0, 1        ; return 0, if nothing found

_KEYBGK_RET_R2  MOVE    R2, R8                  ; return new key
                NOT     R2, R2
                AND     R2, @R1                 ; unmark this key as new
                RBRA    _KEYBGK_RET, 1

_KEYBGK_RET_0   MOVE    0, R8
_KEYBGK_RET     DECRB
                RET

; internal helper function for the typematic repeat of a pressed key
; R8:  key code of the key
; R9:  pointer to the PRESSED flag-word
; R10: pointer to the two typematic words of the key (see keyboard_vars.asm):
;      the time of the press or of the last repeat, then the state
; R12: the time now (IO$CYC_MID)
_KEYB_TYPEMATIC INCRB

                MOVE    R10, R0
                MOVE    @R0++, R1               ; R1: time, R0: ptr. to state
                CMP     0, @R0                  ; first scan of this press?
                RBRA    _KEYB_TYPEM_P, !Z       ; no
                MOVE    R12, @R10               ; yes: remember the time and..
                MOVE    1, @R0                  ; ..wait for the delay
                RBRA    _KEYB_TYPEM_RET, 1

_KEYB_TYPEM_P   MOVE    R12, R2
                SUB     R1, R2                  ; R2: ticks since that time
                MOVE    M2M$TYPEMATIC_DLY, R3   ; state 1: wait for the delay
                CMP     1, @R0
                RBRA    _KEYB_TYPEM_C, Z
                MOVE    M2M$TYPEMATIC_SPD, R3   ; state 2: repeat speed
_KEYB_TYPEM_C   CMP     R3, R2                  ; time not yet over?
                RBRA    _KEYB_TYPEM_RET, N      ; yes: return

                MOVE    R8, R1                  ; no: unpress the key, so..
                NOT     R1, R1                  ; ..that the next scan sees..
                AND     R1, @R9                 ; ..it as a new key
                MOVE    R12, @R10               ; remember the time and..
                MOVE    2, @R0                  ; ..repeat from now on

_KEYB_TYPEM_RET DECRB
                RET
