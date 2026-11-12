; ****************************************************************************
; C64 for MEGA65 QNICE ROM
;
; Keyboard shortcuts F9 .. F14 (issue #142): the core specific part. The
; machinery (key detection, invisible menu sessions, messages, deferred
; saving) is in M2M/rom/shortcuts.asm.
;
; done by sy2002 in 2026 and licensed under GPL v3
; ****************************************************************************

; SC_KEY callback function (see M2M/rom/shortcuts.asm):
;
; Called from the main loop while the OSM is closed, when the user presses
; F9, F11 or F13 with or without Shift.
;
; Input:  R8: function key: 0 = F9, 1 = F10 (Shift+F9), 2 = F11, 3 = F12,
;             4 = F13, 5 = F14
; Output: Carry = 1: the action shall repeat while the key is held down
;         R8..R12 stay unchanged
;
; Every function key has a picker (radio group) in the submenu Keyboard
; Shortcuts of config.vhd that lists the same 11 actions in the same order.
; C64_OSM_SC_F9 .. C64_OSM_SC_F14 (mega65.vhd) are the flat menu indexes of
; the first action ("Off") of each picker. The hardware handles "Freeze" on
; its own (keyboard.vhd, cartridge.vhd), so the Shell ignores it.

SC_A_COUNT      .EQU 11                         ; amount of actions per picker

SC_PICKERS      .DW     C64_OSM_SC_F9, C64_OSM_SC_F10, C64_OSM_SC_F11
                .DW     C64_OSM_SC_F12, C64_OSM_SC_F13, C64_OSM_SC_F14

                ; actions in the order of the pickers in config.vhd
SC_ACTIONS      .DW     _SCK_NONE               ; Off
                .DW     _SCK_NONE               ; Freeze (hardware)
                .DW     _SCK_MOUNT8             ; Mount drive 8
                .DW     _SCK_MOUNT9             ; Mount drive 9
                .DW     _SCK_NEXT8              ; Next disk drive 8
                .DW     _SCK_NEXT9              ; Next disk drive 9
                .DW     _SCK_PRG                ; Load PRG
                .DW     _SCK_CRT                ; Load CRT
                .DW     _SCK_FLIP               ; Flip joysticks
                .DW     _SCK_VOLDOWN            ; Volume down
                .DW     _SCK_VOLUP              ; Volume up

SC_KEY          SYSCALL(enter, 1)

                MOVE    SC_PICKERS, R0          ; R0: flat index of the first
                ADD     R8, R0                  ; action of the picker of this
                MOVE    @R0, R0                 ; function key
                XOR     R1, R1                  ; R1: action
_SCK_FIND       MOVE    R0, R8
                ADD     R1, R8
                RSUB    M2M$GET_SETTING, 1      ; R9 = 1: action selected
                CMP     1, R9
                RBRA    _SCK_FOUND, Z
                ADD     1, R1
                CMP     SC_A_COUNT, R1
                RBRA    _SCK_FIND, !Z
                RBRA    _SCK_NONE, 1            ; defensive: none selected

_SCK_FOUND      MOVE    SC_ACTIONS, R2          ; run the action
                ADD     R1, R2
                MOVE    @R2, R2
                ABRA    R2, 1

_SCK_MOUNT8     XOR     R8, R8                  ; drive 8 = virtual drive 0
                MOVE    C64_OPTM_G_MOUNT_8, R9
                RBRA    _SCK_MOUNT, 1
_SCK_MOUNT9     MOVE    1, R8                   ; drive 9 = virtual drive 1
                MOVE    C64_OPTM_G_MOUNT_9, R9
_SCK_MOUNT      RSUB    SC_DRIVE_OK, 1          ; drive off or busy? message
                RBRA    _SCK_NONE, !C
                MOVE    R9, R8                  ; select the mount line of the
                RSUB    SC$PRESS, 1             ; drive: opens the browser
                RBRA    _SCK_NONE, 1

_SCK_NEXT8      XOR     R8, R8
                RBRA    _SCK_NEXT, 1
_SCK_NEXT9      MOVE    1, R8
_SCK_NEXT       RSUB    SC_DRIVE_OK, 1
                RBRA    _SCK_NONE, !C
                MOVE    R8, R4                  ; R4: virtual drive
                MOVE    R8, R9                  ; next disk inside an
                MOVE    SC_NEXT_IN, R8          ; invisible menu session
                RSUB    SC$SESSION, 1           ; R8: status of VD_NEXT_DISK
                CMP     0, R8                   ; 0: mounted, message is ready
                RBRA    _SCK_NEXT_1, !Z
                RSUB    SC$MSG_SHOW, 1
                RBRA    _SCK_NONE, 1
_SCK_NEXT_1     CMP     R8, 5                   ; unknown status (> 5)?
                RBRA    _SCK_NEXT_2, !N
                MOVE    5, R8                   ; yes: error (5)
_SCK_NEXT_2     MOVE    SC_NEXT_MSGS, R9        ; message for this status
                ADD     R8, R9                  ; (none for 1 and 4: the
                MOVE    @R9, R9                 ; browser was shown instead)
                RBRA    _SCK_NONE, Z
                MOVE    R4, R8
                RSUB    SC_DRIVE_MSG, 1
                RBRA    _SCK_NONE, 1

_SCK_PRG        MOVE    C64_OPTM_G_LOAD_PRG, R8 ; the PRG line of the menu:
                RSUB    SC$PRESS, 1             ; browser, load, autostart
                RBRA    _SCK_NONE, 1

_SCK_CRT        MOVE    C64_OPTM_G_MOUNT_CRT, R8 ; the CRT line of the menu:
                RSUB    SC$PRESS, 1             ; switches to the simulated
                RBRA    _SCK_NONE, 1            ; cartridge, opens the browser

_SCK_FLIP       MOVE    C64_OSM_FLIP_JOYS, R8   ; toggle "Flip joystick ports"
                RSUB    M2M$GET_SETTING, 1      ; R9: current state
                XOR     1, R9
                RSUB    M2M$SET_SETTING, 1
                RSUB    SC$SAVE_LATER, 1
                MOVE    SC_S_FLIPPED, R1
                CMP     1, R9
                RBRA    _SCK_FLIP_1, Z
                MOVE    SC_S_NORMAL, R1
_SCK_FLIP_1     MOVE    SC_S_JOYS, R8
                MOVE    R1, R9
                RSUB    SC$TOAST2, 1
                RBRA    _SCK_NONE, 1

_SCK_VOLDOWN    MOVE    1, R8                   ; one line down = 5% less
                RBRA    _SCK_VOL, 1
_SCK_VOLUP      MOVE    0xFFFF, R8              ; one line up = 5% more
_SCK_VOL        RSUB    SC_VOLUME, 1
                RBRA    _SCK_REPEAT, 1          ; repeat while held down

_SCK_NONE       AND     0xFFFB, SR              ; Carry = 0: no key repeat
                RBRA    _SCK_RET, 1
_SCK_REPEAT     OR      0x0004, SR              ; Carry = 1: key repeat
_SCK_RET        SYSCALL(leave, 1)
                RET

                ; messages for the statuses 0..5 of VD_NEXT_DISK
SC_NEXT_MSGS    .DW     0, 0, SC_S_NONEXT, SC_S_SAVING, 0, SC_S_NEXTERR

; Check if a virtual drive can take a disk image right now; if not, show the
; reason as a message.
; Input:  R8: virtual drive (0 = drive 8, 1 = drive 9)
; Output: Carry = 1: OK; all registers stay unchanged
SC_DRIVE_OK     SYSCALL(enter, 1)
                MOVE    R8, R4                  ; R4: virtual drive
                MOVE    C64_OSM_DRV8_OFF, R5    ; R5, R6: menu lines of the
                MOVE    C64_OSM_DRV8_1581, R6   ; modes Off and Internal 1581
                CMP     0, R4                   ; of this drive
                RBRA    _SCDO_1, Z
                MOVE    C64_OSM_DRV9_OFF, R5
                MOVE    C64_OSM_DRV9_1581, R6
_SCDO_1         MOVE    R5, R8                  ; drive switched off?
                RSUB    M2M$GET_SETTING, 1
                MOVE    SC_S_OFF, R1
                CMP     1, R9
                RBRA    _SCDO_NO, Z
                MOVE    R6, R8                  ; physical drive (the MEGA65
                RSUB    M2M$GET_SETTING, 1      ; internal floppy as 1581)?
                MOVE    SC_S_1581, R1
                CMP     1, R9
                RBRA    _SCDO_NO, Z
                MOVE    R4, R8                  ; unsaved data being written?
                MOVE    VD_CACHE_DIRTY, R9      ; (the menu does not replace
                RSUB    VD_DRV_READ, 1          ; such a disk image either)
                MOVE    SC_S_SAVING, R1
                CMP     0, R8
                RBRA    _SCDO_NO, !Z
                OR      0x0004, SR              ; Carry = 1: OK
                RBRA    _SCDO_RET, 1
_SCDO_NO        MOVE    R4, R8                  ; message: drive + reason
                MOVE    R1, R9
                RSUB    SC_DRIVE_MSG, 1
                AND     0xFFFB, SR              ; Carry = 0
_SCDO_RET       SYSCALL(leave, 1)
                RET

; Message "Drive 8" or "Drive 9" plus the string in R9.
; SC_DRIVE_START only starts the message, SC_DRIVE_MSG also shows it.
; Input: R8: virtual drive (0 or 1); all registers stay unchanged
SC_DRIVE_MSG    RSUB    SC_DRIVE_START, 1
                MOVE    R8, @--SP
                MOVE    R9, R8
                RSUB    SC$MSG_ADD, 1
                MOVE    @SP++, R8
                RBRA    SC$MSG_SHOW, 1

SC_DRIVE_START  INCRB
                MOVE    R8, R0
                MOVE    SC_S_DRIVE, R8          ; "Drive "
                RSUB    SC$MSG_START, 1
                MOVE    SC_DIGITS, R8           ; "8" or "9"
                MOVE    R8, R1
                MOVE    R0, @R1
                ADD     0x0038, @R1++
                MOVE    0, @R1
                RSUB    SC$MSG_ADD, 1
                MOVE    R0, R8
                DECRB
                RET

; Routine for SC$SESSION: mount the next disk image of a drive (see
; VD_NEXT_DISK). If no disk image is mounted or the SD card changed, open the
; file browser instead, like the shortcut "Mount drive". The message for a
; successful mount is prepared in here because the file name is only valid
; until the next file operation (the session saves the settings afterwards).
; Input:  R8: virtual drive
; Output: R8: status of VD_NEXT_DISK
SC_NEXT_IN      SYSCALL(enter, 1)
                MOVE    R8, R4                  ; R4: virtual drive
                RSUB    VD_NEXT_DISK, 1         ; R8: status, R9: file name
                MOVE    R8, R5                  ; R5: status
                RBRA    _SCNI_1, !Z             ; MOVE sets Z: status 0?
                MOVE    R4, R8                  ; "Drive 8: <file name>"
                RSUB    SC_DRIVE_START, 1
                MOVE    SC_S_COLON, R8
                RSUB    SC$MSG_ADD, 1
                MOVE    R9, R8
                RSUB    SC$MSG_ADD, 1
                RBRA    _SCNI_RET, 1

_SCNI_1         CMP     1, R5                   ; nothing mounted or SD card
                RBRA    _SCNI_BROWSE, Z         ; changed: file browser
                CMP     4, R5
                RBRA    _SCNI_RET, !Z
_SCNI_BROWSE    MOVE    C64_OPTM_G_MOUNT_8, R8
                CMP     0, R4
                RBRA    _SCNI_2, Z
                MOVE    C64_OPTM_G_MOUNT_9, R8
_SCNI_2         RSUB    SC$PRESS_IN, 1

_SCNI_RET       MOVE    R5, R8
                MOVE    R8, @--SP               ; return R8 through leave
                SYSCALL(leave, 1)
                MOVE    @SP++, R8
                RET

; Volume one step (5%) up or down, show the new volume as a message.
; Input: R8: 1 = down, 0xFFFF = up; all registers stay unchanged
SC_VOLUME       SYSCALL(enter, 1)
                MOVE    R8, R6                  ; R6: direction
                XOR     R1, R1                  ; R1: selected line (0 = 100%)
_SCV_FIND       MOVE    C64_OSM_VOLUME_100, R8
                ADD     R1, R8
                RSUB    M2M$GET_SETTING, 1
                CMP     1, R9
                RBRA    _SCV_FOUND, Z
                ADD     1, R1
                CMP     21, R1
                RBRA    _SCV_FIND, !Z
                XOR     R1, R1                  ; defensive: none = 100%

_SCV_FOUND      MOVE    R1, R2                  ; R2: new line
                ADD     R6, R2
                CMP     0xFFFF, R2              ; above 100%?
                RBRA    _SCV_CHK0, !Z
                XOR     R2, R2
_SCV_CHK0       CMP     21, R2                  ; below 0%?
                RBRA    _SCV_SET, !Z
                MOVE    20, R2
_SCV_SET        CMP     R1, R2                  ; at the limit: no change
                RBRA    _SCV_MSG, Z
                MOVE    C64_OSM_VOLUME_100, R8  ; set the new line first and
                ADD     R2, R8                  ; then clear the old one, so
                MOVE    1, R9                   ; that the hardware never sees
                RSUB    M2M$SET_SETTING, 1      ; "no line" (would be 100%)
                MOVE    C64_OSM_VOLUME_100, R8
                ADD     R1, R8
                XOR     R9, R9
                RSUB    M2M$SET_SETTING, 1
                RSUB    SC$SAVE_LATER, 1

_SCV_MSG        MOVE    R2, R8                  ; R3: percent = 100 - 5 x line
                MOVE    5, R9
                SYSCALL(mulu, 1)
                MOVE    100, R3
                SUB     R10, R3
                MOVE    SC_S_VOLUME, R8         ; "Volume: <percent>%"
                RSUB    SC$MSG_START, 1
                MOVE    SC_DIGITS, R5
                CMP     100, R3
                RBRA    _SCV_TENS, !Z
                MOVE    0x0031, @R5++           ; "100"
                MOVE    0x0030, @R5++
                MOVE    0x0030, @R5++
                RBRA    _SCV_DONE, 1
_SCV_TENS       MOVE    R3, R8
                MOVE    10, R9
                SYSCALL(divu, 1)                ; R10: tens, R11: ones
                CMP     0, R10
                RBRA    _SCV_ONES, Z
                ADD     0x0030, R10
                MOVE    R10, @R5++
_SCV_ONES       ADD     0x0030, R11
                MOVE    R11, @R5++
_SCV_DONE       MOVE    0, @R5
                MOVE    SC_DIGITS, R8
                RSUB    SC$MSG_ADD, 1
                MOVE    SC_S_PERCENT, R8
                RSUB    SC$MSG_ADD, 1
                RSUB    SC$MSG_SHOW, 1
                SYSCALL(leave, 1)
                RET

SC_S_DRIVE      .ASCII_W "Drive "
SC_S_COLON      .ASCII_W ": "
SC_S_OFF        .ASCII_W " is off"
SC_S_1581       .ASCII_W " is the internal 1581"
SC_S_SAVING     .ASCII_W " is still saving"
SC_S_NONEXT     .ASCII_W ": no other disk image"
SC_S_NEXTERR    .ASCII_W ": next disk failed"
SC_S_JOYS       .ASCII_W "Joystick ports: "
SC_S_FLIPPED    .ASCII_W "flipped"
SC_S_NORMAL     .ASCII_W "normal"
SC_S_VOLUME     .ASCII_W "Volume: "
SC_S_PERCENT    .ASCII_W "%"
