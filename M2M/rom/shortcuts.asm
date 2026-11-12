; ****************************************************************************
; MiSTer2MEGA65 (M2M) QNICE ROM
;
; Keyboard shortcuts (C64MEGA65 issue #142)
;
; While the OSM is closed, the keys F9, F11 and F13 of the MEGA65 keyboard and
; their Shift layer (F10, F12 and F14) act as shortcuts. This file contains the
; core-independent machinery; the core decides what each key does by
; implementing the callback SC_KEY in its m2m-rom.asm:
;
; SC_KEY        Input:  R8 = function key: 0 = F9, 1 = F10, ... 5 = F14
;               Output: Carry = 1, if the action shall repeat while the key is
;                       held down (e.g. volume); R8..R12 stay unchanged
;               Called from the main loop while the OSM is closed.
;
; Routines that the core can use in SC_KEY:
;
; SC$PRESS      Selects a menu line without showing the menu: the real menu
;               engine (OPTM_RUN) runs invisibly and receives the key Return on
;               the first line of the given menu group. Every callback and
;               every safety mechanism of the menu runs exactly as if the user
;               had opened the menu and selected the line (file browser,
;               mounting, loading, saving the settings, ...).
; SC$SESSION    Runs a routine inside such an invisible menu session, for
;               actions that need the data structures of the menu but no menu
;               line (e.g. "next disk"). The routine can use SC$PRESS_IN.
; SC$TOAST      Shows a one-line message for one second while the core keeps
;               running: keyboard and joysticks stay connected to the core.
; SC$SAVE_LATER Saves the settings about three seconds after the last change
;               that a shortcut made while the OSM was closed (the regular
;               saving in HELP_MENU only notices changes made in the menu).
;
; done by sy2002 in 2026 and licensed under GPL v3
; ****************************************************************************

; IO$CYC_MID counts with 50 MHz / 65536 = 763 Hz
SC_T_TOAST      .EQU 763                        ; message: 1 second
SC_T_SAVE       .EQU 2289                       ; deferred saving: 3 seconds
SC_T_REP1       .EQU 381                        ; key repeat: first after 0.5 s
SC_T_REPN       .EQU 115                        ; key repeat: then every 0.15 s

SC_TOAST_LEN    .EQU 47                         ; maximum message length

; ----------------------------------------------------------------------------
; SC$INIT: Initialize the variables (call once at the start of the Shell)
; ----------------------------------------------------------------------------

SC$INIT         INCRB
                MOVE    SC_REP_KEY, R0          ; the first four variables of
                XOR     R1, R1                  ; shortcuts_vars.asm: key
                MOVE    R1, @R0++               ; repeat, message, pending
                MOVE    R1, @R0++               ; save and ROSM_FORCE
                MOVE    R1, @R0++
                MOVE    R1, @R0
                DECRB
                RET

; ----------------------------------------------------------------------------
; SC$MAIN: Main loop hook, call it right before HELP_MENU
;
; Input:  R8: new key from KEYB$GETKEY (0 = none)
; Output: All registers stay unchanged
; ----------------------------------------------------------------------------

SC$MAIN         SYSCALL(enter, 1)
                MOVE    R8, R7                  ; R7: new key

                ; Help opens the menu right after this routine: remove a
                ; visible message first and stop a key repeat
                CMP     M2M$KEY_HELP, R7
                RBRA    _SCM_TICKS, !Z
                RSUB    SC$TOAST_OFF, 1
                MOVE    SC_REP_KEY, R0
                MOVE    0, @R0

_SCM_TICKS      RSUB    _SC_TOAST_TICK, 1       ; message timeout
                RSUB    _SC_SAVE_TICK, 1        ; deferred saving
                RSUB    _SC_REP_TICK, 1         ; key repeat

                MOVE    R7, R8                  ; new shortcut key pressed?
                RSUB    _SC_FKEY, 1             ; R8: 0..5 or 0xFFFF
                CMP     0xFFFF, R8
                RBRA    _SCM_RET, Z             ; no

                MOVE    R8, R6                  ; R6: function key 0..5
                MOVE    SC_REP_KEY, R0          ; a new key ends a key repeat
                MOVE    0, @R0
                RSUB    SC_KEY, 1               ; core callback; C=1: repeat
                RBRA    _SCM_RET, !C

                MOVE    SC_REP_KEY, R0          ; arm the key repeat
                MOVE    R7, @R0
                MOVE    SC_REP_FKEY, R0
                MOVE    R6, @R0
                MOVE    SC_REP_DLY, R0
                MOVE    SC_T_REP1, @R0
                MOVE    IO$CYC_MID, R0
                MOVE    SC_REP_T, R1
                MOVE    @R0, @R1

_SCM_RET        SYSCALL(leave, 1)
                RET

; Translate a new key into a function key index: 0 = F9, 1 = F10, 2 = F11,
; 3 = F12, 4 = F13, 5 = F14 and 0xFFFF for any other key. Shift is sampled
; right when the function key goes down, so pressing or releasing Shift while
; the key is held does not change the meaning of the key press.
; Input: R8: new key; Output: R8: index or 0xFFFF
_SC_FKEY        INCRB
                XOR     R0, R0                  ; F9
                CMP     M2M$KEY_F9, R8
                RBRA    _SCF_SHIFT, Z
                MOVE    2, R0                   ; F11
                CMP     M2M$KEY_F11, R8
                RBRA    _SCF_SHIFT, Z
                MOVE    4, R0                   ; F13
                CMP     M2M$KEY_F13, R8
                RBRA    _SCF_SHIFT, Z
                MOVE    0xFFFF, R8              ; not a shortcut key
                RBRA    _SCF_RET, 1

_SCF_SHIFT      MOVE    M2M$KEYBOARD, R1        ; Shift held right now?
                MOVE    @R1, R1                 ; (the bits are low active)
                AND     M2M$KEY_SHIFT, R1
                RBRA    _SCF_NOSHIFT, !Z        ; bit set: Shift not pressed
                ADD     1, R0                   ; F10, F12 or F14
_SCF_NOSHIFT    MOVE    R0, R8
_SCF_RET        DECRB
                RET

; Key repeat: call SC_KEY again while the key is held down
_SC_REP_TICK    INCRB
                MOVE    SC_REP_KEY, R0
                MOVE    @R0, R1                 ; R1: held key (0 = none)
                RBRA    _SCRT_RET, Z
                MOVE    M2M$KEYBOARD, R2        ; still held? (low active)
                MOVE    @R2, R2
                AND     R1, R2
                RBRA    _SCRT_STOP, !Z          ; released: stop repeating

                MOVE    SC_REP_T, R3
                MOVE    IO$CYC_MID, R4
                MOVE    @R4, R4                 ; R4: now
                MOVE    R4, R5
                SUB     @R3, R5                 ; R5: ticks since last trigger
                MOVE    SC_REP_DLY, R6
                CMP     @R6, R5                 ; delay > ticks?
                RBRA    _SCRT_RET, N            ; yes: not yet

                MOVE    R4, @R3                 ; remember this trigger
                MOVE    SC_T_REPN, @R6          ; faster from now on
                MOVE    R8, R7                  ; save R8
                MOVE    SC_REP_FKEY, R8
                MOVE    @R8, R8
                RSUB    SC_KEY, 1               ; trigger the action again
                MOVE    R7, R8                  ; (MOVE keeps the Carry flag)
                RBRA    _SCRT_RET, C            ; still repeatable

_SCRT_STOP      MOVE    0, @R0
_SCRT_RET       DECRB
                RET

; ----------------------------------------------------------------------------
; SC$PRESS: Select a menu line without showing the menu
;
; Input:  R8: menu group id (the first line of this group is selected)
; Output: R8: 1 = the line was selected, 0 = it was not (e.g. hidden because
;             of a dependency or not found)
; ----------------------------------------------------------------------------

SC$PRESS        INCRB
                MOVE    R9, R0                  ; save R9
                MOVE    R8, R9                  ; R9: group id
                MOVE    SC$PRESS_IN, R8
                RSUB    SC$SESSION, 1           ; R8: result
                MOVE    R0, R9
                DECRB
                RET

; ----------------------------------------------------------------------------
; SC$SESSION: Run a routine inside an invisible menu session
;
; HELP_MENU builds all data structures of the menu as if the user had pressed
; Help, then calls the routine instead of running the interactive menu and
; finally saves the settings and reconnects keyboard and joysticks to the
; core, exactly as when the user closes the menu. The menu window is never
; shown, only a file browser that the routine might open.
;
; Input:  R8: address of the routine; it gets R9 (below) in R8, returns its
;             result in R8 and may use SC$PRESS_IN
;         R9: input for the routine
; Output: R8: result of the routine (0xFFFF if the menu could not run)
; ----------------------------------------------------------------------------

SC$SESSION      SYSCALL(enter, 1)
                RSUB    SC$TOAST_OFF, 1         ; no message during a session

                MOVE    SC_S_ROUTINE, R0
                MOVE    R8, @R0
                MOVE    SC_S_ARG, R0
                MOVE    R9, @R0
                MOVE    SC_S_RESULT, R0
                MOVE    0xFFFF, @R0

                MOVE    OPTM_DIRECT, R1         ; tell HELP_MENU (and the
                MOVE    1, @R1                  ; mount code) to stay invisible
                MOVE    M2M$KEY_HELP, R8        ; same entry as the Help key
                RSUB    HELP_MENU, 1
                MOVE    0, @R1

                MOVE    @R0, R8                 ; R8: result of the routine
                MOVE    R8, @--SP               ; return R8 through leave
                SYSCALL(leave, 1)
                MOVE    @SP++, R8
                RET

; Called by HELP_MENU inside the invisible session
SC$IN_SESSION   SYSCALL(enter, 1)
                MOVE    SC_S_ARG, R8
                MOVE    @R8, R8
                MOVE    SC_S_ROUTINE, R0
                MOVE    @R0, R0
                ASUB    R0, 1                   ; R8: result of the routine
                MOVE    SC_S_RESULT, R0
                MOVE    R8, @R0
                SYSCALL(leave, 1)
                RET

; ----------------------------------------------------------------------------
; SC$PRESS_IN: Select a menu line; only valid inside an invisible session
;
; The menu engine starts at the main menu level with the cursor on the first
; line of the group and gets its keys from _SC_GETKEY: Return (only if the
; cursor really is on that line) and then Help to close the menu. Afterwards
; the menu level of the user is restored, so that the next Help shows the
; menu where the user left it.
;
; Input:  R8: menu group id
; Output: R8: 1 = selected, 0 = not selected
; ----------------------------------------------------------------------------

SC$PRESS_IN     SYSCALL(enter, 1)

                MOVE    HEAP, R0                ; R0: groups array on the heap
                ADD     OPTM_IR_GROUPS, R0
                MOVE    @R0, R0
                MOVE    OPTM_ICOUNT, R1         ; R1: amount of menu lines
                MOVE    @R1, R1
                XOR     R2, R2                  ; R2: flat index
_SCPI_FIND      MOVE    @R0++, R3
                AND     0x00FF, R3              ; group id of this line
                CMP     R8, R3
                RBRA    _SCPI_FOUND, Z
                ADD     1, R2
                CMP     R1, R2
                RBRA    _SCPI_FIND, !Z
                XOR     R8, R8                  ; group not found
                RBRA    _SCPI_RET, 1

_SCPI_FOUND     MOVE    SC_P_TARGET, R0
                MOVE    R2, @R0
                MOVE    SC_P_STEP, R0
                MOVE    0, @R0
                MOVE    SC_P_DONE, R0
                MOVE    0, @R0

                MOVE    OPTM_MENULEVEL, R4      ; start at the main menu
                MOVE    @R4, R5                 ; R5: level of the user
                MOVE    0, @R4
                MOVE    OPTM_DATA, R6           ; key function of the heap
                MOVE    @R6, R6                 ; copy of the init record
                ADD     OPTM_FP_GETKEY, R6      ; (HELP_MENU copies a fresh
                MOVE    @R6, R7                 ; record on every open)
                MOVE    _SC_GETKEY, @R6

                MOVE    R2, R8                  ; cursor on the target line
                RSUB    OPTM_RUN, 1

                MOVE    R7, @R6                 ; restore the key function
                MOVE    R5, @R4                 ; restore the menu level
                MOVE    SC_P_DONE, R8
                MOVE    @R8, R8

_SCPI_RET       MOVE    R8, @--SP               ; return R8 through leave
                SYSCALL(leave, 1)
                MOVE    @SP++, R8
                RET

; Scripted key function for OPTM_RUN (see SC$PRESS_IN)
_SC_GETKEY      INCRB
                MOVE    SC_P_STEP, R0
                CMP     0, @R0                  ; first key?
                RBRA    _SCGK_CLOSE, !Z         ; no: close the menu
                MOVE    1, @R0
                MOVE    OPTM_CUR_SEL, R1        ; is the cursor on the target?
                MOVE    SC_P_TARGET, R2         ; (OPTM_RUN moves the cursor
                CMP     @R1, @R2                ; away from a hidden line)
                RBRA    _SCGK_CLOSE, !Z         ; no: do not select anything
                MOVE    SC_P_DONE, R0
                MOVE    1, @R0
                MOVE    OPTM_KEY_SELECT, R8     ; Return on the target line
                RBRA    _SCGK_RET, 1
_SCGK_CLOSE     MOVE    OPTM_KEY_CLOSE, R8      ; Help: close the menu
_SCGK_RET       DECRB
                RET

; ----------------------------------------------------------------------------
; SC$TOAST: Show a one-line message at the bottom of the screen for 1 second
;
; Keyboard and joysticks stay connected to the core, the core keeps running.
; Long messages are clipped. Showing a new message replaces the current one.
; SC$MSG_START and SC$MSG_ADD build a message from several strings in
; SC_TOAST_BUF and SC$MSG_SHOW shows it; SC$TOAST does all of it for one
; string and SC$TOAST2 for two strings.
;
; Input:  R8 (and R9 for SC$TOAST2): zero terminated string(s)
; Output: All registers stay unchanged
; ----------------------------------------------------------------------------

SC$TOAST2       RSUB    SC$MSG_START, 1
                MOVE    R8, @--SP
                MOVE    R9, R8
                RSUB    SC$MSG_ADD, 1
                MOVE    @SP++, R8
                RBRA    SC$MSG_SHOW, 1

SC$TOAST        RSUB    SC$MSG_START, 1
                RBRA    SC$MSG_SHOW, 1

SC$MSG_START    INCRB
                MOVE    SC_TOAST_BUF, R0
                MOVE    0, @R0
                DECRB
                ; fall through to SC$MSG_ADD

SC$MSG_ADD      INCRB
                MOVE    SC_TOAST_BUF, R0        ; find the end
                XOR     R1, R1                  ; R1: length
_SCMA_END       CMP     0, @R0
                RBRA    _SCMA_COPY, Z
                ADD     1, R0
                ADD     1, R1
                RBRA    _SCMA_END, 1
_SCMA_COPY      MOVE    R8, R2
_SCMA_LOOP      CMP     SC_TOAST_LEN, R1        ; buffer full?
                RBRA    _SCMA_TERM, Z
                MOVE    @R2++, R3
                RBRA    _SCMA_TERM, Z           ; end of the string
                MOVE    R3, @R0++
                ADD     1, R1
                RBRA    _SCMA_LOOP, 1
_SCMA_TERM      MOVE    0, @R0
                DECRB
                RET

SC$MSG_SHOW     SYSCALL(enter, 1)

                MOVE    SC_TOAST_BUF, R8        ; R3: length, clipped to the
                SYSCALL(strlen, 1)              ; screen width minus frame and
                MOVE    R9, R3                  ; one space on each side
                MOVE    SCR$SYS_DX, R0
                MOVE    @R0, R0
                SUB     4, R0
                CMP     R0, R3                  ; fits (maximum > length)?
                RBRA    _SCMS_1, N              ; yes
                MOVE    R0, R3
                MOVE    SC_TOAST_BUF, R1
                ADD     R3, R1
                MOVE    0, @R1

_SCMS_1         MOVE    R3, R6                  ; R6: width = length + 4
                ADD     4, R6
                MOVE    SCR$SYS_DX, R4          ; R4: x = centered
                MOVE    @R4, R4
                SUB     R6, R4
                AND     0xFFFB, SR              ; clear C (shifted in)
                SHR     1, R4
                MOVE    SCR$SYS_DY, R5          ; R5: y = bottom, one line free
                MOVE    @R5, R5
                SUB     4, R5

                RSUB    SCR$CLR, 1              ; also clears colors that the
                MOVE    R4, R8                  ; menu might have left behind
                MOVE    R5, R9
                MOVE    R6, R10
                MOVE    3, R11
                RSUB    SCR$PRINTFRAME, 1
                MOVE    SC_TOAST_BUF, R8        ; print the message
                MOVE    R4, R9
                ADD     2, R9
                MOVE    R5, R10
                ADD     1, R10
                RSUB    SCR$PRINTSTRXY, 1

                SWAP    R4, R4                  ; OSM window: x|y
                OR      R5, R4
                MOVE    M2M$OSM_XY, R1
                MOVE    R4, @R1
                SWAP    R6, R6                  ; OSM window: dx|dy
                OR      3, R6
                MOVE    M2M$OSM_DXDY, R1
                MOVE    R6, @R1
                MOVE    M2M$CSR, R0             ; show it
                OR      M2M$CSR_OSM, @R0

                MOVE    SC_TOAST_ON, R0         ; start the timeout
                MOVE    1, @R0
                MOVE    IO$CYC_MID, R0
                MOVE    SC_TOAST_T, R1
                MOVE    @R0, @R1

                SYSCALL(leave, 1)
                RET

; Hide a visible message
SC$TOAST_OFF    INCRB
                MOVE    SC_TOAST_ON, R0
                CMP     0, @R0
                RBRA    _SCTO_RET, Z
                MOVE    0, @R0
                RSUB    SCR$OSM_OFF, 1
_SCTO_RET       DECRB
                RET

; Hide the message after one second
_SC_TOAST_TICK  INCRB
                MOVE    SC_TOAST_ON, R0
                CMP     0, @R0
                RBRA    _SCTT_RET, Z
                MOVE    SC_TOAST_T, R1
                MOVE    IO$CYC_MID, R2
                MOVE    @R2, R2
                SUB     @R1, R2                 ; R2: ticks since it was shown
                CMP     SC_T_TOAST, R2          ; less than one second?
                RBRA    _SCTT_RET, N            ; yes: keep it
                RSUB    SC$TOAST_OFF, 1
_SCTT_RET       DECRB
                RET

; ----------------------------------------------------------------------------
; SC$SAVE_LATER: Save the settings about three seconds after the last change
;
; Use it after changing a setting with M2M$SET_SETTING while the OSM is
; closed. Every call restarts the waiting time, so a key repeat (e.g. volume)
; leads to one single write access to the SD card.
; ----------------------------------------------------------------------------

SC$SAVE_LATER   INCRB
                MOVE    SC_SAVE_PEND, R0
                MOVE    1, @R0
                MOVE    IO$CYC_MID, R0
                MOVE    SC_SAVE_T, R1
                MOVE    @R0, @R1
                DECRB
                RET

_SC_SAVE_TICK   INCRB
                MOVE    SC_SAVE_PEND, R0
                CMP     0, @R0
                RBRA    _SCST_RET, Z
                MOVE    SC_SAVE_T, R1
                MOVE    IO$CYC_MID, R2
                MOVE    @R2, R3
                SUB     @R1, R3                 ; R3: ticks since last change
                CMP     SC_T_SAVE, R3           ; less than three seconds?
                RBRA    _SCST_RET, N            ; yes: wait

                MOVE    ROSM_FORCE, R4          ; save even though ROSM_CHANGES
                MOVE    1, @R4                  ; does not see this change
                RSUB    ROSM_SAVE, 1
                CMP     2, @R4                  ; 2: a write cache was dirty,
                RBRA    _SCST_DONE, !Z          ; nothing saved: try again in
                MOVE    @R2, @R1                ; three seconds
                RBRA    _SCST_CLR, 1
_SCST_DONE      MOVE    0, @R0                  ; not pending anymore
_SCST_CLR       MOVE    0, @R4
_SCST_RET       DECRB
                RET
