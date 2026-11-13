; ****************************************************************************
; MiSTer2MEGA65 (M2M) QNICE ROM
;
; Headless testbed for the keyboard shortcuts (C64MEGA65 issue #142):
; M2M/rom/shortcuts.asm plus the core specific CORE/m2m-rom/shortcuts_c64.asm.
;
; The runner shortcuts_test.py generates rewired copies of both modules in
; which the hardware registers (cycle counter, keyboard, CSR and OSM window)
; are RAM variables of this testbed, and it generates the menu constants. It
; also cuts the tail of HELP_MENU (options.asm, from _HLP_HEAP2_OK on: the
; invisible session, the visible menu and the common exit with the waiting
; time and the reconnect of keyboard and joysticks) out of the sources, which
; runs behind a stub of the head of HELP_MENU. This testbed stubs the menu
; engine, the settings, the screen, the mount code and the drives; every stub
; prints a trace line that the runner compares with independently computed
; expectations.
;
; Run it with:  python3 shortcuts_test.py
;
; done by sy2002 in 2026 and licensed under GPL v3
; ****************************************************************************

#include "../../QNICE/dist_kit/sysdef.asm"
#include "../../QNICE/dist_kit/monitor.def"
#include "../sysdef.asm"
#include "shortcuts_tbgen_const.asm"

                .ORG    0x8000

                MOVE    S_BEGIN, R8
                RSUB    TB_PUTS, 1
                RSUB    TB_RESET, 1

                ; --------------------------------------------------------
                ; T1: function key resolution incl. the Shift layer
                ; --------------------------------------------------------
                MOVE    S_T1, R8
                RSUB    TB_PUTS, 1
                MOVE    TB_FK_KEYS, R4
_T1_KEY         MOVE    @R4++, R5               ; R5: key (0xFFFF = end)
                CMP     0xFFFF, R5
                RBRA    _T1_END, Z
                MOVE    0xFFFF, R6              ; Shift up, then Shift down
                RSUB    _T1_ONE, 1
                MOVE    0xDFFF, R6              ; M2M$KEY_SHIFT = 0x2000
                RSUB    _T1_ONE, 1
                RBRA    _T1_KEY, 1
_T1_ONE         MOVE    TB_KEYB, R0
                MOVE    R6, @R0
                MOVE    R5, R8
                RSUB    _SC_FKEY, 1
                MOVE    R8, R7
                MOVE    S_FK, R8
                RSUB    TB_TAG, 1
                MOVE    R5, R8
                RSUB    TB_HEX, 1
                MOVE    R6, R8
                RSUB    TB_HEX, 1
                MOVE    R7, R8
                RSUB    TB_HEX, 1
                RSUB    TB_NL, 1
                RET
_T1_END         MOVE    TB_KEYB, R0
                MOVE    0xFFFF, @R0

                ; --------------------------------------------------------
                ; T2: volume down 21 times (F13), up 21 times (F14)
                ; --------------------------------------------------------
                MOVE    S_T2, R8
                RSUB    TB_PUTS, 1
                MOVE    21, R4
_T2_DOWN        MOVE    4, R8                   ; F13: Volume down
                RSUB    TB_SCKEY, 1
                SUB     1, R4
                RBRA    _T2_DOWN, !Z
                MOVE    21, R4
_T2_UP          MOVE    5, R8                   ; F14: Volume up
                RSUB    TB_SCKEY, 1
                SUB     1, R4
                RBRA    _T2_UP, !Z
                RSUB    TB_VOLBITS, 1           ; exactly one bit: line 0

                ; --------------------------------------------------------
                ; T3: flip joysticks (F12 set to Flip) twice
                ; --------------------------------------------------------
                MOVE    S_T3, R8
                RSUB    TB_PUTS, 1
                MOVE    C64_OSM_SC_F12, R8      ; picker F12: Flip joysticks
                MOVE    8, R9
                RSUB    TB_PICK, 1
                MOVE    SC_SAVE_PEND, R0
                MOVE    0, @R0
                MOVE    3, R8
                RSUB    TB_SCKEY, 1
                MOVE    SC_SAVE_PEND, R8        ; deferred save is pending
                MOVE    @R8, R8
                RSUB    TB_VAL, 1
                MOVE    3, R8
                RSUB    TB_SCKEY, 1

                ; --------------------------------------------------------
                ; T4: Mount drive 8 / 9: drive modes, dirty cache, success
                ; --------------------------------------------------------
                MOVE    S_T4, R8
                RSUB    TB_PUTS, 1
                MOVE    C64_OSM_DRV8_IMG_MNT, R8 ; drive 8: Internal 1581
                MOVE    2, R9
                RSUB    TB_DRVMODE, 1
                MOVE    2, R8
                RSUB    TB_SCKEY, 1
                MOVE    C64_OSM_DRV8_IMG_MNT, R8 ; drive 8: Off
                MOVE    3, R9
                RSUB    TB_DRVMODE, 1
                MOVE    2, R8
                RSUB    TB_SCKEY, 1
                MOVE    C64_OSM_DRV8_IMG_MNT, R8 ; drive 8: If mounted, dirty
                XOR     R9, R9
                RSUB    TB_DRVMODE, 1
                MOVE    TB_DIRTY, R0
                MOVE    1, @R0
                MOVE    2, R8
                RSUB    TB_SCKEY, 1
                MOVE    TB_DIRTY, R0            ; clean: the mount line is
                MOVE    0, @R0                  ; selected invisibly
                MOVE    OPTM_MENULEVEL, R0      ; the user left the menu in
                MOVE    7, @R0                  ; region 7
                MOVE    2, R8
                RSUB    TB_SCKEY, 1
                MOVE    OPTM_MENULEVEL, R8      ; restored: 7
                MOVE    @R8, R8
                RSUB    TB_VAL, 1
                MOVE    TB_REC, R8              ; key function restored: 1
                ADD     OPTM_FP_GETKEY, R8
                MOVE    @R8, R8
                CMP     TB_REALGK, R8
                MOVE    0, R8
                RBRA    _T4_GK, !Z
                MOVE    1, R8
_T4_GK          RSUB    TB_VAL, 1
                MOVE    C64_OSM_SC_F12, R8      ; F12: Mount drive 9 (Off)
                MOVE    3, R9
                RSUB    TB_PICK, 1
                MOVE    3, R8
                RSUB    TB_SCKEY, 1

                ; --------------------------------------------------------
                ; T5: target line hidden (the cursor lands elsewhere)
                ; --------------------------------------------------------
                MOVE    S_T5, R8
                RSUB    TB_PUTS, 1
                MOVE    TB_RUN_SHIFT, R0
                MOVE    1, @R0
                MOVE    2, R8
                RSUB    TB_SCKEY, 1
                MOVE    SC_P_DONE, R8           ; nothing was selected: 0
                MOVE    @R8, R8
                RSUB    TB_VAL, 1
                MOVE    TB_RUN_SHIFT, R0
                MOVE    0, @R0
                MOVE    C64_OPTM_G_HDMI_ZOOM, R8 ; group without a line in the
                RSUB    SC$PRESS, 1             ; fake menu: not found: 0
                RSUB    TB_VAL, 1

                ; --------------------------------------------------------
                ; T6: Next disk drive 8 with every status of VD_NEXT_DISK
                ; --------------------------------------------------------
                MOVE    S_T6, R8
                RSUB    TB_PUTS, 1
                MOVE    C64_OSM_SC_F11, R8      ; F11: Next disk drive 8
                MOVE    4, R9
                RSUB    TB_PICK, 1
                MOVE    TB_ND_LIST, R4
_T6_NEXT        MOVE    @R4++, R5
                CMP     0xFFFF, R5
                RBRA    _T6_END, Z
                MOVE    TB_ND_STATUS, R0
                MOVE    R5, @R0
                MOVE    2, R8
                RSUB    TB_SCKEY, 1
                RBRA    _T6_NEXT, 1
_T6_END

                ; --------------------------------------------------------
                ; T7: Load PRG (F12) and Load CRT (F10, default)
                ; --------------------------------------------------------
                MOVE    S_T7, R8
                RSUB    TB_PUTS, 1
                MOVE    C64_OSM_SC_F12, R8
                MOVE    6, R9
                RSUB    TB_PICK, 1
                MOVE    3, R8
                RSUB    TB_SCKEY, 1
                MOVE    1, R8
                RSUB    TB_SCKEY, 1
                MOVE    0, R8                   ; F9: Freeze: Shell ignores it
                RSUB    TB_SCKEY, 1
                MOVE    C64_OSM_SC_F9, R8       ; F9: Off
                XOR     R9, R9
                RSUB    TB_PICK, 1
                MOVE    0, R8
                RSUB    TB_SCKEY, 1

                ; --------------------------------------------------------
                ; T8: message clipping and window geometry
                ; --------------------------------------------------------
                MOVE    S_T8, R8
                RSUB    TB_PUTS, 1
                MOVE    S_LONG, R8
                RSUB    SC$TOAST, 1
                RSUB    TB_OSMREGS, 1
                MOVE    S_HI, R8
                RSUB    SC$TOAST, 1
                RSUB    TB_OSMREGS, 1

                ; --------------------------------------------------------
                ; T9: message timeout incl. counter wrap-around
                ; --------------------------------------------------------
                MOVE    S_T9, R8
                RSUB    TB_PUTS, 1
                MOVE    1000, R8
                RSUB    TB_TIME, 1
                MOVE    S_HI, R8
                RSUB    SC$TOAST, 1
                MOVE    1762, R8
                RSUB    TB_TICKT, 1
                MOVE    1763, R8
                RSUB    TB_TICKT, 1
                MOVE    65000, R8
                RSUB    TB_TIME, 1
                MOVE    S_HI, R8
                RSUB    SC$TOAST, 1
                MOVE    226, R8
                RSUB    TB_TICKT, 1
                MOVE    227, R8
                RSUB    TB_TICKT, 1

                ; --------------------------------------------------------
                ; T10: deferred saving, also blocked by a dirty write cache
                ; --------------------------------------------------------
                MOVE    S_T10, R8
                RSUB    TB_PUTS, 1
                MOVE    5000, R8
                RSUB    TB_TIME, 1
                RSUB    SC$SAVE_LATER, 1
                MOVE    7288, R8
                RSUB    TB_TICKS, 1
                MOVE    7289, R8
                RSUB    TB_TICKS, 1
                MOVE    TB_SAVE_BLOCK, R0
                MOVE    1, @R0
                MOVE    100, R8
                RSUB    TB_TIME, 1
                RSUB    SC$SAVE_LATER, 1
                MOVE    2389, R8
                RSUB    TB_TICKS, 1
                MOVE    TB_SAVE_BLOCK, R0
                MOVE    0, @R0
                MOVE    4677, R8
                RSUB    TB_TICKS, 1
                MOVE    4678, R8
                RSUB    TB_TICKS, 1

                ; --------------------------------------------------------
                ; T11: key repeat through SC$MAIN (F13 = Volume down)
                ; --------------------------------------------------------
                MOVE    S_T11, R8
                RSUB    TB_PUTS, 1
                RSUB    TB_VOL100, 1
                MOVE    10000, R8
                RSUB    TB_TIME, 1
                MOVE    TB_KEYB, R0             ; F13 held down
                MOVE    0xEFFF, @R0
                MOVE    M2M$KEY_F13, R8
                RSUB    TB_MAIN, 1
                MOVE    10380, R8
                RSUB    TB_MAINT, 1
                MOVE    10381, R8
                RSUB    TB_MAINT, 1
                MOVE    10495, R8
                RSUB    TB_MAINT, 1
                MOVE    10496, R8
                RSUB    TB_MAINT, 1
                MOVE    TB_KEYB, R0             ; released
                MOVE    0xFFFF, @R0
                MOVE    20000, R8
                RSUB    TB_MAINT, 1
                MOVE    SC_REP_KEY, R8          ; repeat ended: 0
                MOVE    @R8, R8
                RSUB    TB_VAL, 1

                ; --------------------------------------------------------
                ; T12: Shift+F13 = F14 (Volume up) through SC$MAIN; Help
                ; removes a visible message
                ; --------------------------------------------------------
                MOVE    S_T12, R8
                RSUB    TB_PUTS, 1
                MOVE    30000, R8
                RSUB    TB_TIME, 1
                MOVE    TB_KEYB, R0             ; Shift and F13 held down
                MOVE    0xCFFF, @R0
                MOVE    M2M$KEY_F13, R8
                RSUB    TB_MAIN, 1
                MOVE    TB_KEYB, R0
                MOVE    0xFFFF, @R0
                MOVE    M2M$KEY_HELP, R8        ; message visible: Help
                RSUB    TB_MAIN, 1
                MOVE    SC_TOAST_ON, R8
                MOVE    @R8, R8
                RSUB    TB_VAL, 1

                ; --------------------------------------------------------
                ; T13: a session waits only if the mount code read a key;
                ; two sessions in a row in both orders
                ; --------------------------------------------------------
                MOVE    S_T13, R8
                RSUB    TB_PUTS, 1
                MOVE    C64_OSM_SC_F11, R8      ; F11: Next disk drive 8
                MOVE    4, R9
                RSUB    TB_PICK, 1
                MOVE    TB_ND_STATUS, R0        ; next image mounted ...
                MOVE    0, @R0
                MOVE    TB_ND_KEYS, R0          ; ... after an error window
                MOVE    1, @R0
                MOVE    2, R8
                RSUB    TB_SCKEY, 1
                MOVE    TB_ND_KEYS, R0          ; ... directly: no key read
                MOVE    0, @R0
                MOVE    2, R8
                RSUB    TB_SCKEY, 1
                MOVE    C64_OSM_SC_F12, R8      ; F12: Mount drive 8: file
                MOVE    2, R9                   ; browser
                RSUB    TB_PICK, 1
                MOVE    3, R8
                RSUB    TB_SCKEY, 1
                MOVE    TB_CB_KEYS, R0          ; the mount code returns
                MOVE    0, @R0                  ; without reading a key
                MOVE    3, R8
                RSUB    TB_SCKEY, 1
                MOVE    C64_OSM_SC_F12, R8      ; F12: Load PRG, no key read
                MOVE    6, R9
                RSUB    TB_PICK, 1
                MOVE    3, R8
                RSUB    TB_SCKEY, 1
                MOVE    C64_OSM_SC_F12, R8      ; F12: Load CRT, no key read
                MOVE    7, R9
                RSUB    TB_PICK, 1
                MOVE    3, R8
                RSUB    TB_SCKEY, 1
                MOVE    TB_CB_KEYS, R0
                MOVE    1, @R0

                ; --------------------------------------------------------
                ; T14: the visible menu (Help key) always waits, whatever
                ; HM_KEYREAD says; last selected line or start line
                ; --------------------------------------------------------
                MOVE    S_T14, R8
                RSUB    TB_PUTS, 1
                MOVE    OPTM_START, R0
                MOVE    1, @R0
                MOVE    TB_VISIBLE, R4
_T14_NEXT       MOVE    @R4++, R5               ; R5: OPTM_SELECTED
                CMP     0xFFFF, R5
                RBRA    _T14_END, Z
                MOVE    OPTM_SELECTED, R0
                MOVE    R5, @R0
                MOVE    HM_KEYREAD, R0
                MOVE    @R4++, @R0
                MOVE    M2M$KEY_HELP, R8
                RSUB    HELP_MENU, 1
                MOVE    OPTM_SELECTED, R8
                MOVE    @R8, R8
                RSUB    TB_VAL, 1
                RBRA    _T14_NEXT, 1
_T14_END

                MOVE    S_DONE, R8
                RSUB    TB_PUTS, 1
                SYSCALL(exit, 1)

; ----------------------------------------------------------------------------
; Testbed helpers
; ----------------------------------------------------------------------------

; reset the fake hardware, the fake menu and the module variables
TB_RESET        INCRB
                MOVE    TB_CFM, R0              ; all settings 0
                MOVE    TB_CFM_SIZE, R1
_TBR_1          MOVE    0, @R0++
                SUB     1, R1
                RBRA    _TBR_1, !Z
                MOVE    TB_DEFAULTS, R0         ; default settings
_TBR_2          MOVE    @R0++, R1
                CMP     0xFFFF, R1
                RBRA    _TBR_3, Z
                MOVE    TB_CFM, R2
                ADD     R1, R2
                MOVE    1, @R2
                RBRA    _TBR_2, 1
_TBR_3          MOVE    TB_KEYB, R0
                MOVE    0xFFFF, @R0
                MOVE    TB_CYC, R0
                MOVE    0, @R0
                MOVE    TB_CSR, R0              ; OSM closed: keyboard and
                MOVE    M2M$CSR_KBD_JOY, @R0    ; joysticks are connected
                MOVE    OPTM_DATA, R0           ; fake init record of the menu
                MOVE    TB_REC, @R0
                MOVE    TB_REC, R0
                ADD     OPTM_FP_GETKEY, R0
                MOVE    TB_REALGK, @R0
                MOVE    HEAP, R0                ; fake groups array
                ADD     OPTM_IR_GROUPS, R0
                MOVE    TB_GROUPS, @R0
                MOVE    OPTM_ICOUNT, R0
                MOVE    TB_GROUPS_N, @R0
                MOVE    OPTM_DIRECT, R0
                MOVE    0, @R0
                MOVE    OPTM_MENULEVEL, R0
                MOVE    0, @R0
                MOVE    HM_KEYREAD, R0
                MOVE    0, @R0
                MOVE    TB_CB_KEYS, R0          ; a selected line opens the
                MOVE    1, @R0                  ; file browser
                MOVE    TB_ND_KEYS, R0          ; next disk: no error window
                MOVE    0, @R0
                RSUB    SC$INIT, 1
                DECRB
                RET

; set the radio picker R8 (flat index of its first item) to item R9
TB_PICK         INCRB
                MOVE    TB_CFM, R0
                ADD     R8, R0
                MOVE    11, R1
_TBP_1          MOVE    0, @R0++
                SUB     1, R1
                RBRA    _TBP_1, !Z
                MOVE    TB_CFM, R0
                ADD     R8, R0
                ADD     R9, R0
                MOVE    1, @R0
                DECRB
                RET

; set the drive mode group (R8: flat index of "If mounted") to item R9
TB_DRVMODE      INCRB
                MOVE    TB_CFM, R0
                ADD     R8, R0
                MOVE    0, @R0
                MOVE    0, @R0++
                MOVE    0, @R0++
                MOVE    0, @R0++
                MOVE    0, @R0
                MOVE    TB_CFM, R0
                ADD     R8, R0
                ADD     R9, R0
                MOVE    1, @R0
                DECRB
                RET

; volume back to 100%
TB_VOL100       INCRB
                MOVE    C64_OSM_VOLUME_100, R8
                MOVE    21, R9
                MOVE    TB_CFM, R0
                ADD     R8, R0
_TBV1_1         MOVE    0, @R0++
                SUB     1, R9
                RBRA    _TBV1_1, !Z
                MOVE    TB_CFM, R0
                ADD     R8, R0
                MOVE    1, @R0
                DECRB
                RET

; print "VB <bits>": the volume line indexes that are set
TB_VOLBITS      INCRB
                MOVE    S_VB, R8
                RSUB    TB_TAG, 1
                XOR     R1, R1
_TBVB_1         MOVE    TB_CFM, R0
                ADD     C64_OSM_VOLUME_100, R0
                ADD     R1, R0
                CMP     0, @R0
                RBRA    _TBVB_2, Z
                MOVE    R1, R8
                RSUB    TB_HEX, 1
_TBVB_2         ADD     1, R1
                CMP     21, R1
                RBRA    _TBVB_1, !Z
                RSUB    TB_NL, 1
                DECRB
                RET

; call SC_KEY(R8) and print "KEY <fkey> C=<carry>"
TB_SCKEY        INCRB
                MOVE    R8, R0
                MOVE    S_KEY, R8
                RSUB    TB_TAG, 1
                MOVE    R0, R8
                RSUB    TB_HEX, 1
                RSUB    TB_NL, 1
                MOVE    R0, R8
                RSUB    SC_KEY, 1
                MOVE    0, R1
                RBRA    _TBSK_1, !C
                MOVE    1, R1
_TBSK_1         MOVE    S_CARRY, R8
                RSUB    TB_TAG, 1
                MOVE    R1, R8
                RSUB    TB_HEX, 1
                RSUB    TB_NL, 1
                MOVE    R0, R8
                DECRB
                RET

; call SC$MAIN with the new key R8
TB_MAIN         INCRB
                MOVE    R8, R0
                MOVE    S_MAIN, R8
                RSUB    TB_TAG, 1
                MOVE    R0, R8
                RSUB    TB_HEX, 1
                MOVE    TB_CYC, R8
                MOVE    @R8, R8
                RSUB    TB_HEX, 1
                RSUB    TB_NL, 1
                MOVE    R0, R8
                RSUB    SC$MAIN, 1
                DECRB
                RET

; set the time to R8 and call SC$MAIN without a new key
TB_MAINT        RSUB    TB_TIME, 1
                MOVE    R8, @--SP
                XOR     R8, R8
                RSUB    TB_MAIN, 1
                MOVE    @SP++, R8
                RET

; set the time to R8, run the message timeout and print "TT <time> <on>"
TB_TICKT        INCRB
                RSUB    TB_TIME, 1
                MOVE    R8, R0
                RSUB    _SC_TOAST_TICK, 1
                MOVE    S_TT, R8
                RSUB    TB_TAG, 1
                MOVE    R0, R8
                RSUB    TB_HEX, 1
                MOVE    SC_TOAST_ON, R8
                MOVE    @R8, R8
                RSUB    TB_HEX, 1
                RSUB    TB_NL, 1
                MOVE    R0, R8
                DECRB
                RET

; set the time to R8, run the deferred save and print
; "ST <time> <pending> <force> <savetime>"
TB_TICKS        INCRB
                RSUB    TB_TIME, 1
                MOVE    R8, R0
                RSUB    _SC_SAVE_TICK, 1
                MOVE    S_ST, R8
                RSUB    TB_TAG, 1
                MOVE    R0, R8
                RSUB    TB_HEX, 1
                MOVE    SC_SAVE_PEND, R8
                MOVE    @R8, R8
                RSUB    TB_HEX, 1
                MOVE    ROSM_FORCE, R8
                MOVE    @R8, R8
                RSUB    TB_HEX, 1
                MOVE    SC_SAVE_T, R8
                MOVE    @R8, R8
                RSUB    TB_HEX, 1
                RSUB    TB_NL, 1
                MOVE    R0, R8
                DECRB
                RET

TB_TIME         INCRB
                MOVE    TB_CYC, R0
                MOVE    R8, @R0
                DECRB
                RET

; print "OSM <xy> <dxdy> <csr>"
TB_OSMREGS      INCRB
                MOVE    S_OSM, R8
                RSUB    TB_TAG, 1
                MOVE    TB_OSM_XY, R8
                MOVE    @R8, R8
                RSUB    TB_HEX, 1
                MOVE    TB_OSM_DXDY, R8
                MOVE    @R8, R8
                RSUB    TB_HEX, 1
                MOVE    TB_CSR, R8
                MOVE    @R8, R8
                RSUB    TB_HEX, 1
                RSUB    TB_NL, 1
                DECRB
                RET

; print "VAL <R8>"
TB_VAL          INCRB
                MOVE    R8, R0
                MOVE    S_VAL, R8
                RSUB    TB_TAG, 1
                MOVE    R0, R8
                RSUB    TB_HEX, 1
                RSUB    TB_NL, 1
                MOVE    R0, R8
                DECRB
                RET

TB_PUTS         SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                RET
TB_TAG          SYSCALL(puts, 1)
                RET
TB_HEX          MOVE    R8, @--SP
                MOVE    S_SPACE, R8
                SYSCALL(puts, 1)
                MOVE    @SP++, R8
                SYSCALL(puthex, 1)
                RET
TB_NL           SYSCALL(crlf, 1)
                RET

; ----------------------------------------------------------------------------
; Stubs of the routines that the modules call
; ----------------------------------------------------------------------------

M2M$GET_SETTING INCRB
                MOVE    TB_CFM, R0
                ADD     R8, R0
                MOVE    @R0, R9
                DECRB
                RET

M2M$SET_SETTING INCRB                           ; "SET <index> <value>"
                MOVE    TB_CFM, R0
                ADD     R8, R0
                MOVE    R9, @R0
                MOVE    R8, R1
                MOVE    S_SET, R8
                RSUB    TB_TAG, 1
                MOVE    R1, R8
                RSUB    TB_HEX, 1
                MOVE    R9, R8
                RSUB    TB_HEX, 1
                RSUB    TB_NL, 1
                MOVE    R1, R8
                DECRB
                RET

SCR$CLR         MOVE    R8, @--SP
                MOVE    S_CLR, R8
                RSUB    TB_PUTS, 1
                MOVE    @SP++, R8
                RET

SCR$OSM_OFF     MOVE    R8, @--SP
                MOVE    S_OFF, R8
                RSUB    TB_PUTS, 1
                MOVE    TB_CSR, R8
                AND     M2M$CSR_UN_OSM, @R8
                MOVE    @SP++, R8
                RET

SCR$PRINTFRAME  INCRB                           ; "FRAME x y dx dy"
                MOVE    R8, R0
                MOVE    S_FRAME, R8
                RSUB    TB_TAG, 1
                MOVE    R0, R8
                RSUB    TB_HEX, 1
                MOVE    R9, R8
                RSUB    TB_HEX, 1
                MOVE    R10, R8
                RSUB    TB_HEX, 1
                MOVE    R11, R8
                RSUB    TB_HEX, 1
                RSUB    TB_NL, 1
                MOVE    R0, R8
                DECRB
                RET

SCR$PRINTSTRXY  INCRB                           ; "TEXT x y |text|"
                MOVE    R8, R0
                MOVE    S_TEXT, R8
                RSUB    TB_TAG, 1
                MOVE    R9, R8
                RSUB    TB_HEX, 1
                MOVE    R10, R8
                RSUB    TB_HEX, 1
                MOVE    S_BAR, R8
                RSUB    TB_TAG, 1
                MOVE    R0, R8
                RSUB    TB_TAG, 1
                MOVE    S_BAR1, R8
                RSUB    TB_PUTS, 1
                MOVE    R0, R8
                DECRB
                RET

ROSM_SAVE       INCRB                           ; "SAVE <force>"
                MOVE    R8, R0
                MOVE    S_SAVE, R8
                RSUB    TB_TAG, 1
                MOVE    ROSM_FORCE, R1
                MOVE    @R1, R8
                RSUB    TB_HEX, 1
                RSUB    TB_NL, 1
                MOVE    TB_SAVE_BLOCK, R2       ; blocked by a dirty cache?
                CMP     0, @R2
                RBRA    _RS_RET, Z
                CMP     0, @R1                  ; like options.asm: report it
                RBRA    _RS_RET, Z              ; to a forced save only
                MOVE    2, @R1
_RS_RET         MOVE    R0, R8
                DECRB
                RET

; HELP_MENU: "HM <key> <direct>", then the stub of its head pauses the core
; and disconnects keyboard and joysticks (like RP_OPTM_START with the C64
; configuration) and the real tail of HELP_MENU runs; afterwards
; "CSR <csr>" shows what the tail left in the CSR
HELP_MENU       INCRB
                MOVE    R8, R0
                MOVE    S_HM, R8
                RSUB    TB_TAG, 1
                MOVE    R0, R8
                RSUB    TB_HEX, 1
                MOVE    OPTM_DIRECT, R8
                MOVE    @R8, R8
                RSUB    TB_HEX, 1
                RSUB    TB_NL, 1
                MOVE    TB_CSR, R1
                AND     M2M$CSR_UN_KBD_JOY, @R1
                OR      M2M$CSR_PAUSE, @R1
                MOVE    R0, R8
                RSUB    TB_HLP, 1
                MOVE    S_CSR, R8
                RSUB    TB_TAG, 1
                MOVE    @R1, R8
                RSUB    TB_HEX, 1
                RSUB    TB_NL, 1
                MOVE    R0, R8
                DECRB
                RET

; the head of HELP_MENU leaves the pointer to the menu groups in R12; the
; tail (generated by the runner) ends with SYSCALL(leave, 1) and RET
TB_HLP          SYSCALL(enter, 1)
                MOVE    TB_GROUPS, R12
#include "shortcuts_tbgen_hlp.asm"

ROSM_REM_OLD    MOVE    R8, @--SP               ; "REM"
                MOVE    S_REM, R8
                RSUB    TB_PUTS, 1
                MOVE    @SP++, R8
                RET

OPTM_SHOW       MOVE    R8, @--SP               ; "SHOW"
                MOVE    S_SHOW, R8
                RSUB    TB_PUTS, 1
                MOVE    @SP++, R8
                RET

SCR$OSM_O_ON    MOVE    R8, @--SP               ; "ON"
                MOVE    S_ON, R8
                RSUB    TB_PUTS, 1
                MOVE    @SP++, R8
                RET

WAIT333MS       INCRB                           ; "WAIT <csr>"
                MOVE    R8, R0
                MOVE    S_WAIT, R8
                RSUB    TB_TAG, 1
                MOVE    TB_CSR, R8
                MOVE    @R8, R8
                RSUB    TB_HEX, 1
                RSUB    TB_NL, 1
                MOVE    R0, R8
                DECRB
                RET

; the menu engine: "RUN <start> <level>", then up to 4 keys "K <key>"
; (Return also prints "CB" for the selection callback; if TB_CB_KEYS is set,
; the callback sets HM_KEYREAD, as the mount code does when it opens the file
; browser)
OPTM_RUN        INCRB
                MOVE    R8, R0
                MOVE    S_RUN, R8
                RSUB    TB_TAG, 1
                MOVE    R0, R8
                RSUB    TB_HEX, 1
                MOVE    OPTM_MENULEVEL, R8
                MOVE    @R8, R8
                RSUB    TB_HEX, 1
                RSUB    TB_NL, 1
                MOVE    TB_RUN_SHIFT, R1        ; cursor lands here
                MOVE    @R1, R1
                ADD     R0, R1
                MOVE    OPTM_CUR_SEL, R2
                MOVE    R1, @R2
                MOVE    4, R3                   ; guard
_OR_KEY         MOVE    OPTM_DATA, R7
                MOVE    @R7, R7
                ADD     OPTM_FP_GETKEY, R7
                MOVE    @R7, R7
                ASUB    R7, 1                   ; R8: key
                MOVE    R8, R4
                MOVE    S_K, R8
                RSUB    TB_TAG, 1
                MOVE    R4, R8
                RSUB    TB_HEX, 1
                RSUB    TB_NL, 1
                CMP     OPTM_KEY_CLOSE, R4
                RBRA    _OR_RET, Z
                CMP     OPTM_KEY_SELECT, R4
                RBRA    _OR_NEXT, !Z
                MOVE    S_CB, R8
                RSUB    TB_PUTS, 1
                MOVE    TB_CB_KEYS, R8
                CMP     0, @R8
                RBRA    _OR_NEXT, Z
                MOVE    HM_KEYREAD, R8
                MOVE    1, @R8
_OR_NEXT        SUB     1, R3
                RBRA    _OR_KEY, !Z
_OR_RET         MOVE    R1, R8
                DECRB
                RET

TB_REALGK       MOVE    OPTM_KEY_CLOSE, R8      ; the real key function is
                RET                             ; never called here

VD_DRV_READ     INCRB                           ; R8: drive, R9: VD_CACHE_DIRTY
                MOVE    TB_DIRTY, R0
                ADD     R8, R0
                MOVE    @R0, R8
                DECRB
                RET

; "ND <drive>"; if TB_ND_KEYS is set, the mount showed an error window and
; sets HM_KEYREAD, as HANDLE_MOUNTING does
VD_NEXT_DISK    INCRB
                MOVE    R8, R0
                MOVE    S_ND, R8
                RSUB    TB_TAG, 1
                MOVE    R0, R8
                RSUB    TB_HEX, 1
                RSUB    TB_NL, 1
                MOVE    TB_ND_KEYS, R8
                CMP     0, @R8
                RBRA    _VND_1, Z
                MOVE    HM_KEYREAD, R8
                MOVE    1, @R8
_VND_1          MOVE    TB_ND_STATUS, R8
                MOVE    @R8, R8
                MOVE    TB_ND_NAME, R9
                DECRB
                RET

; ----------------------------------------------------------------------------
; The modules under test (rewired copies, generated by the runner)
; ----------------------------------------------------------------------------

#include "shortcuts_tbgen_mod.asm"
#include "shortcuts_tbgen_c64.asm"

; ----------------------------------------------------------------------------
; Test data
; ----------------------------------------------------------------------------

TB_FK_KEYS      .DW     M2M$KEY_F9, M2M$KEY_F11, M2M$KEY_F13, M2M$KEY_F1
                .DW     M2M$KEY_HELP, M2M$KEY_SHIFT, 0, 0xFFFF

                ; the default menu settings that matter here
TB_DEFAULTS     .DW     C64_OSM_DRV8_IMG_MNT, C64_OSM_DRV9_OFF
                .DW     C64_OSM_VOLUME_100
                .DW     TB_DEF_F9, TB_DEF_F10, TB_DEF_F11  ; default action
                .DW     TB_DEF_F12, TB_DEF_F13, TB_DEF_F14 ; of each picker
                .DW     0xFFFF

                ; fake menu: headline, line, 8:%s, text, 9:%s, text, PRG, CRT,
                ; Close
TB_GROUPS       .DW     0x1000, 0x0200, 0x8801, 0x0000, 0x8802, 0x0000
                .DW     0x8003, 0x8005, OPTM_CLOSE
TB_GROUPS_N     .EQU    9

                ; visible menu: OPTM_SELECTED and HM_KEYREAD before the call
TB_VISIBLE      .DW     2, 0, 2, 1, 8, 0, 8, 1, 0xFFFF

TB_ND_LIST      .DW     0, 2, 3, 1, 4, 5, 7, 0xFFFF
TB_ND_NAME      .ASCII_W "GAME-SIDE-B.D64"

S_BEGIN         .ASCII_W "== BEGIN =="
S_DONE          .ASCII_W "DONE"
S_T1            .ASCII_W "== T1 function keys"
S_T2            .ASCII_W "== T2 volume"
S_T3            .ASCII_W "== T3 flip"
S_T4            .ASCII_W "== T4 mount"
S_T5            .ASCII_W "== T5 hidden"
S_T6            .ASCII_W "== T6 next disk"
S_T7            .ASCII_W "== T7 prg crt"
S_T8            .ASCII_W "== T8 message"
S_T9            .ASCII_W "== T9 message timeout"
S_T10           .ASCII_W "== T10 deferred save"
S_T11           .ASCII_W "== T11 key repeat"
S_T12           .ASCII_W "== T12 shift layer and help"
S_T13           .ASCII_W "== T13 sessions with and without key"
S_T14           .ASCII_W "== T14 visible menu"
S_REM           .ASCII_W "REM"
S_SHOW          .ASCII_W "SHOW"
S_ON            .ASCII_W "ON"
S_WAIT          .ASCII_W "WAIT"
S_CSR           .ASCII_W "CSR"
S_FK            .ASCII_W "FK"
S_KEY           .ASCII_W "KEY"
S_CARRY         .ASCII_W "C"
S_MAIN          .ASCII_W "MAIN"
S_SET           .ASCII_W "SET"
S_CLR           .ASCII_W "CLR"
S_OFF           .ASCII_W "OFF"
S_FRAME         .ASCII_W "FRAME"
S_TEXT          .ASCII_W "TEXT"
S_BAR           .ASCII_W " |"
S_BAR1          .ASCII_W "|"
S_SAVE          .ASCII_W "SAVE"
S_HM            .ASCII_W "HM"
S_RUN           .ASCII_W "RUN"
S_K             .ASCII_W "K"
S_CB            .ASCII_W "CB"
S_ND            .ASCII_W "ND"
S_VB            .ASCII_W "VB"
S_TT            .ASCII_W "TT"
S_ST            .ASCII_W "ST"
S_OSM           .ASCII_W "OSM"
S_VAL           .ASCII_W "VAL"
S_SPACE         .ASCII_W " "
S_HI            .ASCII_W "Hi"
S_LONG          .ASCII_W "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwx"

; ----------------------------------------------------------------------------
; Variables
; ----------------------------------------------------------------------------

#include "shortcuts_tbgen_vars.asm"

TB_CYC          .BLOCK 1                        ; fake IO$CYC_MID
TB_KEYB         .BLOCK 1                        ; fake M2M$KEYBOARD
TB_CSR          .BLOCK 1                        ; fake M2M$CSR
TB_OSM_XY       .BLOCK 1                        ; fake M2M$OSM_XY
TB_OSM_DXDY     .BLOCK 1                        ; fake M2M$OSM_DXDY
TB_REC          .BLOCK 20                       ; fake menu init record
TB_DIRTY        .BLOCK 2                        ; write caches of drive 8, 9
TB_ND_STATUS    .BLOCK 1                        ; result of VD_NEXT_DISK
TB_RUN_SHIFT    .BLOCK 1                        ; OPTM_RUN cursor offset
TB_SAVE_BLOCK   .BLOCK 1                        ; ROSM_SAVE: dirty cache
TB_CB_KEYS      .BLOCK 1                        ; selection reads keys
TB_ND_KEYS      .BLOCK 1                        ; next disk reads keys
OPTM_DIRECT     .BLOCK 1
HM_KEYREAD      .BLOCK 1
OPTM_SELECTED   .BLOCK 1
OPTM_START      .BLOCK 1
OPTM_MENULEVEL  .BLOCK 1
OPTM_DATA       .BLOCK 1
OPTM_CUR_SEL    .BLOCK 1
OPTM_ICOUNT     .BLOCK 1
SCR$SYS_DX      .DW     45
SCR$SYS_DY      .DW     33
TB_CFM_SIZE     .EQU    300
TB_CFM          .BLOCK  300                     ; one word per menu line
HEAP            .BLOCK  20
