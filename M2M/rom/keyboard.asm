; ****************************************************************************
; MiSTer2MEGA65 (M2M) QNICE ROM
;
; Keyboard controller (expects low-active keys in the QNICE register)
;
; The basic idea is: A key first has to be released until it can be counted
; as pressed again.
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
                MOVE    KEYB_CDN_DELAY, R0      ; clear the typematic vars.
                MOVE    KEYB_TYPEM_WORDS, R1
_KEYB_INIT_LOOP MOVE    0, @R0++
                SUB     1, R1
                RBRA    _KEYB_INIT_LOOP, !Z
                DECRB
                RET

; perform one scan iteration; meant to be called repeatedly
KEYB$SCAN       INCRB
                MOVE    R8, R0
                MOVE    R9, R1
                MOVE    R10, R2
                MOVE    R11, R3
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
                ; its delay counter and trigger flag cleared, which is done
                ; inline, so that a scan costs about as much as it did when
                ; only up and down had a typematic repeat
                MOVE    R1, R9                  ; R9: pointer to PRESSED

                MOVE    R0, R4                  ; cursor down
                AND     M2M$KEY_DOWN, R4
                RBRA    _KEYB_SCAN_DN0, Z
                MOVE    M2M$KEY_DOWN, R8
                MOVE    KEYB_CDN_DELAY, R10
                MOVE    KEYB_CDN_TRIG, R11
                RSUB    _KEYB_TYPEMATIC, 1
                RBRA    _KEYB_SCAN_UP, 1
_KEYB_SCAN_DN0  MOVE    KEYB_CDN_DELAY, R4      ; not pressed: clear delay..
                MOVE    0, @R4++                ; ..counter and trigger flag
                MOVE    0, @R4

_KEYB_SCAN_UP   MOVE    R0, R4                  ; cursor up
                AND     M2M$KEY_UP, R4
                RBRA    _KEYB_SCAN_UP0, Z
                MOVE    M2M$KEY_UP, R8
                MOVE    KEYB_CUP_DELAY, R10
                MOVE    KEYB_CUP_TRIG, R11
                RSUB    _KEYB_TYPEMATIC, 1
                RBRA    _KEYB_SCAN_LF, 1
_KEYB_SCAN_UP0  MOVE    KEYB_CUP_DELAY, R4
                MOVE    0, @R4++
                MOVE    0, @R4

_KEYB_SCAN_LF   MOVE    R0, R4                  ; cursor left
                AND     M2M$KEY_LEFT, R4
                RBRA    _KEYB_SCAN_LF0, Z
                MOVE    M2M$KEY_LEFT, R8
                MOVE    KEYB_CLF_DELAY, R10
                MOVE    KEYB_CLF_TRIG, R11
                RSUB    _KEYB_TYPEMATIC, 1
                RBRA    _KEYB_SCAN_RT, 1
_KEYB_SCAN_LF0  MOVE    KEYB_CLF_DELAY, R4
                MOVE    0, @R4++
                MOVE    0, @R4

_KEYB_SCAN_RT   MOVE    R0, R4                  ; cursor right
                AND     M2M$KEY_RIGHT, R4
                RBRA    _KEYB_SCAN_RT0, Z
                MOVE    M2M$KEY_RIGHT, R8
                MOVE    KEYB_CRT_DELAY, R10
                MOVE    KEYB_CRT_TRIG, R11
                RSUB    _KEYB_TYPEMATIC, 1
                RBRA    _KEYB_SCAN_END, 1
_KEYB_SCAN_RT0  MOVE    KEYB_CRT_DELAY, R4
                MOVE    0, @R4++
                MOVE    0, @R4

_KEYB_SCAN_END  DECRB
                MOVE    R0, R8
                MOVE    R1, R9
                MOVE    R2, R10
                MOVE    R3, R11
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

; internal helper function for typematic repeat
; R8: key code of key that shall be handled
; R9: pointer to PRESSED flag-word
; R10: pointer to speed/delay counter
; R11: pointer to delay-is-over-flag (trigger)
_KEYB_TYPEMATIC INCRB

                MOVE    @R9, R0
                AND     R8, R0                  ; to-be-handled key pressed?
                RBRA    _KEYB_TYPEM_DTD, Z      ; no: delete trg./dly. vars
                CMP     1, @R11                 ; typem, rep. alrdy triggered?
                RBRA    _KEYB_TYPEM_T, Z        ; yes: choose rep. speed
                MOVE    M2M$TYPEMATIC_DLY, R6   ; no: choose delay speed
                RBRA    _KEYB_TYPEM_C, 1
_KEYB_TYPEM_T   MOVE    M2M$TYPEMATIC_SPD, R6   ; repeat speed     
_KEYB_TYPEM_C   ADD     1, @R10                 ; inc speed/delay counter
                CMP     R6, @R10                ; speed/delay reached?      
                RBRA    _KEYB_TYPEM_RET, !Z     ; no: return

                MOVE    R8, R0                  ; yes: unpress key
                NOT     R0, R0
                AND     R0, @R9
                MOVE    1, @R11                 ; set triggered flag
                RBRA    _KEYB_TYPEM_DTO, 1      ; clear delay and return

_KEYB_TYPEM_DTD MOVE    0, @R11                 ; clear trigger flag
_KEYB_TYPEM_DTO MOVE    0, @R10                 ; clear speed/delay counter

_KEYB_TYPEM_RET DECRB
                RET
