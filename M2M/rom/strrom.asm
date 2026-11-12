; ****************************************************************************
; MiSTer2MEGA65 (M2M) QNICE ROM
;
; String ROM: message strings that are stored outside of the firmware ROM
;
; QNICE stores one character per 16-bit word and the firmware ROM ends at
; 0x7000, where the 4k MMIO window starts. Message strings are therefore the
; most expensive content of the firmware ROM. In a release build, the strings
; between the two marker comments
;
;       ;STRROM_BEGIN
;       ...
;       ;STRROM_END
;
; are not assembled into the firmware ROM. make_rom.sh moves them into a block
; RAM of their own, the QNICE device M2M$STRROM, and leaves one word per label
; in the firmware ROM: the position of the string in the string ROM. These
; words form the table between STRROM$TAB and STRROM$TAB_END. The label of a
; string ROM string is the address of its table entry. This address is called
; the handle of the string.
;
; A handle is not a pointer to characters. STRROM$OPEN turns it into one by
; selecting the string ROM in the 4k MMIO window, and STRROM$CLOSE selects the
; device and the window again that were active before. The routines that
; output strings do this by themselves, so that a handle can be passed to
;
;       SYSCALL(puts, 1)        (IO$PUTS in monitor/io_library_m2m.asm)
;       LOG_STR                 (tools.asm)
;       SCR$PRINTSTR            (screen.asm) and therefore SCR$PRINTSTRXY
;       FATAL and FATAL_IDX     (shell.asm)
;
; exactly like a pointer to a string. Everything else needs a pointer: the
; string functions of the QNICE Monitor (strlen, strcpy, strcmp, strstr, ...),
; M2M$CHK_EXT, M2M$RPL_S, OPTM_LIVE_TEXT and any code that reads characters or
; does arithmetic with the address. Strings that are used like this stay
; outside of the markers, or the code brackets its accesses with STRROM$OPEN
; and STRROM$CLOSE.
;
; Rules for the text between the markers (make_rom.sh enforces them):
;
; * Only labels and .ASCII_W/.ASCII_P lines, comments and empty lines.
; * The last line needs to be an .ASCII_W, so that the last string ends
;   inside of the markers.
; * A string including its zero terminator needs to fit into one 4k window.
; * A line has at most 200 characters. Longer strings are split into several
;   lines with .ASCII_P.
; * A backslash is not followed by a backslash or by a double quote: the
;   assembler has no encoding for these two sequences.
;
; The string ROM is used in release builds only. If RELEASE is not defined,
; then the firmware runs in RAM and the puts of the QNICE Monitor in ROM does
; not know about handles. The STRROM_TABLE marker below is therefore part of
; release builds only, and without it make_rom.sh leaves all strings where
; they stand. The same is true for everything that is assembled without
; make_rom.sh, for example the testbeds: the markers are plain comments there.
; In all these cases the table is empty, STRROM$OPEN finds no handle and all
; strings are ordinary strings.
;
; done by sy2002 in 2026 and licensed under GPL v3
; ****************************************************************************

; ----------------------------------------------------------------------------
; STRROM$OPEN
;
; Makes the string in R8 readable as a normal zero-terminated string. If R8 is
; the handle of a string ROM string, then the string ROM is selected and the
; address of the string inside the 4k MMIO window is returned. Any other value
; is returned unchanged: it is treated as a pointer to an ordinary string.
;
; The device and the window that are selected at the time of the call are
; pushed on the stack. STRROM$CLOSE pops and selects them again, so each
; STRROM$OPEN needs exactly one STRROM$CLOSE at the same stack level.
;
; While a string ROM string is open, the 4k MMIO window shows the string ROM.
; Code that selects another device in the meantime needs to select the string
; ROM again before it reads the next character. SAVE_DEVSEL and RESTORE_DEVSEL
; are made for this.
;
; The status flags are not changed, so that a routine that brackets its work
; with STRROM$OPEN and STRROM$CLOSE treats the flags of its caller exactly as
; it would without the two calls. IO$PUTS depends on this: it preserves the
; Carry and the Overflow flag.
;
; Input:  R8: string pointer or string ROM handle
; Output: R8: string pointer, valid until STRROM$CLOSE
;         Two words are added to the stack
; ----------------------------------------------------------------------------

STRROM$OPEN     INCRB
                MOVE    SR, R4                  ; R4: flags of the caller
                MOVE    @SP++, R0               ; R0: return address

                MOVE    M2M$RAMROM_DEV, R1      ; remember the selection of..
                MOVE    @R1, @--SP              ; ..the caller on the stack
                MOVE    M2M$RAMROM_4KWIN, R2
                MOVE    @R2, @--SP

                CMP     STRROM$TAB, R8          ; handles point into the table
                RBRA    _STRROM$O_RET, N        ; R8 < STRROM$TAB: pointer
                CMP     STRROM$TAB_END, R8
                RBRA    _STRROM$O_RET, !N       ; R8 >= STRROM$TAB_END: ptr.

                MOVE    @R8, R8                 ; R8: position in string ROM
                MOVE    M2M$STRROM, @R1
                MOVE    R8, R3                  ; window = position / 4096
                AND     0xFFFB, SR              ; SHR shifts in the Carry flag
                SHR     12, R3
                MOVE    R3, @R2
                AND     0x0FFF, R8              ; address inside the window
                ADD     M2M$RAMROM_DATA, R8

_STRROM$O_RET   MOVE    R0, @--SP               ; return address
                MOVE    R4, SR                  ; flags as on entry
                DECRB
                RET

; ----------------------------------------------------------------------------
; STRROM$CLOSE
;
; Selects the device and the 4k window that were active when the matching
; STRROM$OPEN was called.
;
; Input:  The two words that STRROM$OPEN added to the stack
; Output: None; no registers are changed, Carry and Overflow are preserved
; ----------------------------------------------------------------------------

STRROM$CLOSE    INCRB
                MOVE    @SP++, R0               ; R0: return address
                MOVE    M2M$RAMROM_4KWIN, R1
                MOVE    @SP++, @R1
                MOVE    M2M$RAMROM_DEV, R1
                MOVE    @SP++, @R1
                MOVE    R0, @--SP               ; return address
                DECRB
                RET

; ----------------------------------------------------------------------------
; Table of the string ROM strings
;
; make_rom.sh inserts one line per string after the marker comment:
;
;       <label> .DW <position of the string in the string ROM>
;
; Keep the lines below together and in this order.
; ----------------------------------------------------------------------------

STRROM$TAB
#ifdef RELEASE
;STRROM_TABLE
#endif
STRROM$TAB_END
