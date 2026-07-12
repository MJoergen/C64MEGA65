; ****************************************************************************
; Commodore 64 for MEGA65 (C64MEGA65) QNICE ROM
;
; Main program that is used to build m2m-rom.rom by make-rom.sh.
; The ROM is loaded by qnice.vhd
;
; The execution starts at the label START_FIRMWARE.
;
; done by sy2002 in 2026 and licensed under GPL v3
; ****************************************************************************

; If the define RELEASE is defined, then the ROM will be a self-contained and
; self-starting ROM that includes the Monitor (QNICE "operating system") and
; jumps to START_FIRMWARE. In this case it is assumed, that the firmware is
; located in ROM and the variables are located in RAM.
;
; If RELEASE is not defined, then it is assumed that we are in the develop and
; debug mode so that the firmware runs in RAM and can be changed/loaded using
; the standard QNICE Monitor mechanisms such as "M/L" or QTransfer.

#define RELEASE

; ----------------------------------------------------------------------------
; Firmware: M2M system
; ----------------------------------------------------------------------------

; main.asm is the mandatory, so always include it
; It jumps to START_FIRMWARE (see below) after the QNICE "operating system"
; called "Monitor" has been included and initialized
#include "../../M2M/rom/main.asm"

; The C64 core uses the Shell of MiSTer2MEGA65
#include "../../M2M/rom/shell.asm"

; ----------------------------------------------------------------------------
; Firmware: Main Code
; ----------------------------------------------------------------------------

START_FIRMWARE  RBRA    START_SHELL, 1

; ----------------------------------------------------------------------------
; Core specific callback functions: Submenus
; ----------------------------------------------------------------------------

; SUBMENU_SUMMARY callback function:
;
; Called when displaying the main menu for every %s that is found in the
; "headline" / starting point of any submenu in config.vhd: You are able to
; change the standard semantics when it comes to summarizing the status of the
; very submenu that is meant by the "headline" / starting point.
;
; Input:
;   R8: pointer to the string that includes the "%s"
;   R9: pointer to the menu item within the M2M$CFG_OPTM_GROUPS structure
;  R10: end-of-menu-marker: if R9 == R10: we reached end of the menu structure
; Output:
;   R8: 0, if no custom SUBMENU_SUMMARY, else:
;       string pointer to completely new headline (do not modify/re-use R8)
;   R9, R10: unchanged
;
; Custom semantics for the "Model: %s" submenu (the one that contains the
; PAL/NTSC machine-mode group): on top of PAL or NTSC, also show the active
; turbo mode and turbo speed, so the user sees the speed-up at a glance without
; entering the submenu:
;
;   no turbo (Off) -> "Model: PAL"          (standard semantics: PAL or NTSC)
;   turbo active   -> "Model: PAL C128 2x"  (machine, turbo mode, turbo speed,
;                                            separated by a single space each)
;
; The Model submenu is recognized by its flat menu index C64_OSM_MODEL, and the
; live selection is read at the fixed indices C64_OSM_MACHINE_PAL / _NTSC,
; C64_OSM_TURBO_OFF / _C128 / _SMART and C64_OSM_TURBO_2X / _3X / _4X. These all
; come from osm_const.asm, which make_rom.sh regenerates from config.vhd plus
; mega65.vhd and which menu_test.py verifies, so reordering the menu cannot
; silently break this callback. Every other submenu returns R8 = 0 (standard
; semantics). The labels (PAL/NTSC/...) are read from the live OPTM_ITEMS so
; that renaming a menu item in config.vhd needs no change here either.
;
; Custom semantics for the "Kernal: %s submenu": Show "JiffyDOS <drive>", if
; either the 1541 or the 1581 JiffyDOS ROM is available and show
; "Jiffy 1541+1581" if both are available.

SUBMENU_SUMMARY MOVE    R9, @--SP               ; save the contract registers
                MOVE    R10, @--SP              ; R9 / R10 across the helper and
                INCRB                           ; M2M$RPL_S calls below

                MOVE    R8, R0                  ; R0: original string (Model: %s)

                ; is this the "Model: %s" opener? its flat index == C64_OSM_MODEL
                SUB     M2M$RAMROM_DATA, R9     ; R9: flat index of this opener
                CMP     C64_OSM_MODEL, R9
                RBRA    _SS_TRY_KERNAL, !Z      ; not Model: try the Kernal opener

                MOVE    HEAP, R1                ; R1: live selected-state array,
                ADD     OPTM_IR_STDSEL, R1      ; one 0/1 per menu line
                MOVE    @R1, R1

                ; R3 := flat index of the selected machine mode (PAL or NTSC)
                MOVE    C64_OSM_MACHINE_PAL, R3
                MOVE    R1, R6
                ADD     R3, R6
                CMP     0, @R6                  ; PAL selected?
                RBRA    _SS_MACH_OK, !Z
                MOVE    C64_OSM_MACHINE_NTSC, R3
                MOVE    R1, R6
                ADD     R3, R6
                CMP     0, @R6                  ; NTSC selected?
                RBRA    _SS_DEFAULT, Z          ; neither (cannot happen): guard

                ; turbo mode: "Off" -> standard semantics; C128/Smart -> custom
_SS_MACH_OK     MOVE    R1, R6
                ADD     C64_OSM_TURBO_OFF, R6
                CMP     0, @R6                  ; turbo "Off" selected?
                RBRA    _SS_DEFAULT, !Z         ; yes -> plain PAL/NTSC
                MOVE    C64_OSM_TURBO_C128, R4
                MOVE    R1, R6
                ADD     R4, R6
                CMP     0, @R6                  ; C128 selected?
                RBRA    _SS_TM_OK, !Z
                MOVE    C64_OSM_TURBO_SMART, R4
                MOVE    R1, R6
                ADD     R4, R6
                CMP     0, @R6                  ; Smart selected?
                RBRA    _SS_DEFAULT, Z          ; none (cannot happen): guard

                ; R4: flat index of the selected turbo mode line
                ; turbo speed: 2x / 3x / 4x
_SS_TM_OK       MOVE    C64_OSM_TURBO_2X, R5
                MOVE    R1, R6
                ADD     R5, R6
                CMP     0, @R6
                RBRA    _SS_TS_OK, !Z
                MOVE    C64_OSM_TURBO_3X, R5
                MOVE    R1, R6
                ADD     R5, R6
                CMP     0, @R6
                RBRA    _SS_TS_OK, !Z
                MOVE    C64_OSM_TURBO_4X, R5
                MOVE    R1, R6
                ADD     R5, R6
                CMP     0, @R6
                RBRA    _SS_DEFAULT, Z          ; none (cannot happen): guard

                ; R5: flat index of the selected turbo speed line
                ; build "<machine> <turbo mode> <turbo speed>" into SS_VALUE,
                ; bounded by SS_VALUE_LEN so an over-long (e.g. future-renamed)
                ; label can never overflow the buffer - it only truncates
_SS_TS_OK       MOVE    SS_VALUE, R8            ; R8: destination cursor
                MOVE    SS_VALUE, R6            ; R6: write limit; the last word
                ADD     SS_VALUE_LEN, R6        ; is reserved for the terminator
                SUB     1, R6
                MOVE    R3, R9                  ; PAL or NTSC
                MOVE    R6, R10
                RSUB    _SS_APPEND_LABEL, 1
                CMP     R6, R8                 ; one space, if room is left
                RBRA    _SS_SP1, Z
                MOVE    0x0020, @R8
                ADD     1, R8
_SS_SP1         MOVE    R4, R9                  ; C128 or Smart
                MOVE    R6, R10
                RSUB    _SS_APPEND_LABEL, 1
                CMP     R6, R8                 ; one space, if room is left
                RBRA    _SS_SP2, Z
                MOVE    0x0020, @R8
                ADD     1, R8
_SS_SP2         MOVE    R5, R9                  ; 2x, 3x or 4x
                MOVE    R6, R10
                RSUB    _SS_APPEND_LABEL, 1
                MOVE    0, @R8                  ; zero-terminate (R8 <= the limit)

                ; splice the value into the original " ... %s" string; this way
                ; the "Model: "/"Kernal: " prefix is kept in config.vhd, not
                ; hardcoded here. Shared by the Model and Kernal branches: the
                ; caller leaves the built value in SS_VALUE and the original
                ; opener string (with %s) in R0.
_SS_SPLICE      MOVE    R0, R8                  ; R8: source string with %s
                MOVE    SS_LINE, R9             ; R9: target line buffer
                MOVE    SS_VALUE, R10           ; R10: replacement for %s
                MOVE    SCR$OSM_O_DX, R11       ; R11: clamp to the menu width,
                MOVE    @R11, R11
                SUB     2, R11
                CMP     SS_LINE_LEN, R11       ; ..but never past SS_LINE itself
                RBRA    _SS_RPL, N              ; R11 < SS_LINE_LEN: it fits
                MOVE    SS_LINE_LEN, R11        ; else clamp to the buffer size
                SUB     1, R11
_SS_RPL         RSUB    M2M$RPL_S, 1            ; clobbers R0..R7, keeps R8..R12
                MOVE    SS_LINE, R8             ; R8: return the custom string
                RBRA    _SS_RET, 1

                ; "Kernal: %s" opener. R0 still holds the opener string and R9
                ; the flat index. When JiffyDOS is the live selection and jd-c64
                ; loaded, render which JiffyDOS drive ROMs are installed instead
                ; of the plain radio label; the tags reflect ROM provisioning
                ; (CRTROM_AUT_LDF), not the live engine (only the 1541 or the
                ; 1581 runs at a time) and not real external IEC drives.
_SS_TRY_KERNAL  CMP     C64_OSM_KERNAL, R9      ; the " Kernal: %s" opener?
                RBRA    _SS_DEFAULT, !Z         ; no: another submenu -> default

                MOVE    HEAP, R1                ; R1: live selected-state array
                ADD     OPTM_IR_STDSEL, R1
                MOVE    @R1, R1
                ADD     C64_OSM_KERNAL_JIFFY, R1
                CMP     0, @R1                  ; JiffyDOS radio selected?
                RBRA    _SS_DEFAULT, Z          ; no -> plain radio label

                MOVE    CRTROM_AUT_LDF, R2      ; R2 -> load-flag base
                CMP     0, @R2                  ; jd-c64 (LDF[0]) loaded?
                RBRA    _SS_DEFAULT, Z          ; no -> do not advertise JiffyDOS

                MOVE    R2, R3                  ; R3 = LDF[1] (jd-c1541)
                ADD     1, R3
                MOVE    @R3, R3
                MOVE    R2, R4                  ; R4 = LDF[2] (jd-c1581)
                ADD     2, R4
                MOVE    @R4, R4

                MOVE    SS_VALUE, R8            ; R8: SS_VALUE build cursor
                MOVE    SS_VALUE, R6            ; R6: write limit (reserve term.)
                ADD     SS_VALUE_LEN, R6
                SUB     1, R6

                ; both drive ROMs -> compact "Jiffy 1541+1581" (fits the 25-col
                ; OSM, unlike the full "JiffyDOS 1541+1581")
                CMP     0, R3
                RBRA    _SS_K_NOT_BOTH, Z
                CMP     0, R4
                RBRA    _SS_K_NOT_BOTH, Z
                MOVE    SS_K_BOTH, R9           ; "Jiffy 1541+1581"
                MOVE    R6, R10
                RSUB    _SS_APPEND_STR, 1
                RBRA    _SS_K_DONE, 1

_SS_K_NOT_BOTH  MOVE    R3, R5                  ; neither drive ROM? (cannot
                ADD     R4, R5                  ; normally happen: boot gate would
                CMP     0, R5                   ; have reverted; guards a runtime
                RBRA    _SS_DEFAULT, Z          ; JiffyDOS pick with no drive ROM)

                ; exactly one drive ROM: reuse "JiffyDOS" from its menu line so
                ; the word itself costs no extra ROM, then append the drive tag
                MOVE    C64_OSM_KERNAL_JIFFY, R9
                MOVE    R6, R10
                RSUB    _SS_APPEND_LABEL, 1     ; append "JiffyDOS"
                MOVE    SS_KT_1581, R9          ; default tag " 1581"
                CMP     0, R3                   ; jd-c1541 present?
                RBRA    _SS_K_TAG, Z
                MOVE    SS_KT_1541, R9          ; yes -> " 1541"
_SS_K_TAG       MOVE    R6, R10
                RSUB    _SS_APPEND_STR, 1

_SS_K_DONE      MOVE    0, @R8                  ; zero-terminate (R8 <= the limit)
                RBRA    _SS_SPLICE, 1           ; share the Model width-clamp tail

_SS_DEFAULT     XOR     R8, R8                  ; R8 = 0: use standard semantics

_SS_RET         DECRB
                MOVE    @SP++, R10              ; restore the contract registers
                MOVE    @SP++, R9
                RET

; Helper for SUBMENU_SUMMARY: append the leading-space-trimmed label of one
; menu line to a destination buffer (no zero terminator is added). The copy is
; bounded by the destination limit, so it can never overflow the buffer.
; CAUTION: a label appended here must not contain a literal backslash (0x5C),
; because that is the first byte of the "\n" line separator in OPTM_ITEMS and is
; therefore treated here as end-of-label.
; Input:  R8: destination cursor, R9: flat menu line index,
;        R10: destination limit (one past the last writable word)
; Output: R8: destination cursor advanced past the copied label (R8 <= R10)
;         R9..R12 are destroyed; R0..R7 are preserved
_SS_APPEND_LABEL INCRB
                MOVE    R8, R0                  ; R0: destination cursor
                MOVE    R9, R1                  ; R1: amount of segments to skip
                MOVE    R10, R4                 ; R4: destination limit
                MOVE    HEAP, R2                ; R2: walk ptr into OPTM_ITEMS,
                ADD     OPTM_IR_ITEMS, R2       ; the \n-separated items string
                MOVE    @R2, R2
_SS_AL_SEG      CMP     0, R1                   ; reached the wanted segment?
                RBRA    _SS_AL_TRIM, Z
                MOVE    R2, R8                  ; no: advance to the next "\n"
                MOVE    OPTM_NL, R9
                SYSCALL(strstr, 1)
                CMP     0, R10                  ; no separator (bad/short index)?
                RBRA    _SS_AL_DONE, Z          ; stop safely instead of deref-ing
                MOVE    R10, R2                 ; R10: ptr to the found "\n"
                ADD     2, R2                   ; skip the two \n characters
                SUB     1, R1
                RBRA    _SS_AL_SEG, 1
_SS_AL_TRIM     CMP     0x0020, @R2             ; skip leading spaces
                RBRA    _SS_AL_COPY, !Z
                ADD     1, R2
                RBRA    _SS_AL_TRIM, 1
_SS_AL_COPY     CMP     R4, R0                  ; destination buffer full?
                RBRA    _SS_AL_DONE, Z          ; yes: truncate, do not overflow
                MOVE    @R2, R3                 ; copy until "\n" (0x5C) or zero
                CMP     0x005C, R3
                RBRA    _SS_AL_DONE, Z
                CMP     0, R3
                RBRA    _SS_AL_DONE, Z
                MOVE    R3, @R0
                ADD     1, R0
                ADD     1, R2
                RBRA    _SS_AL_COPY, 1
_SS_AL_DONE     MOVE    R0, R8                  ; return the advanced dest cursor
                DECRB
                RET

; Helper for SUBMENU_SUMMARY: append a zero-terminated literal string to a
; destination buffer (no terminator added). Bounded by the destination limit,
; so it can never overflow the buffer. Companion to _SS_APPEND_LABEL, which
; copies from an OPTM_ITEMS menu line; this one copies a plain string literal.
; Input:  R8: destination cursor, R9: source string,
;        R10: destination limit (one past the last writable word)
; Output: R8: destination cursor advanced past the copied string (R8 <= R10)
;         R0..R7 and R9..R12 are preserved
_SS_APPEND_STR  INCRB
                MOVE    R8, R0                  ; R0: destination cursor
                MOVE    R9, R1                  ; R1: source pointer
                MOVE    R10, R2                 ; R2: destination limit
_SS_AS_COPY     CMP     R2, R0                  ; destination buffer full?
                RBRA    _SS_AS_DONE, Z          ; yes: truncate, do not overflow
                MOVE    @R1, R3                 ; copy until the zero terminator
                CMP     0, R3
                RBRA    _SS_AS_DONE, Z
                MOVE    R3, @R0
                ADD     1, R0
                ADD     1, R1
                RBRA    _SS_AS_COPY, 1
_SS_AS_DONE     MOVE    R0, R8                  ; return the advanced dest cursor
                DECRB
                RET

; ----------------------------------------------------------------------------
; Core specific callback functions: File browsing and disk image mounting
; ----------------------------------------------------------------------------

; FILTER_FILES callback function:
;
; Called by the file- and directory browser. Used to make sure that the 
; browser is only showing valid files and directories.
;
;
; Input:
;   R8: Name of the file in capital letters
;   R9: 0=file, 1=directory
;  R10: Context (CTX_* constants in sysdef.asm)
;  R11: Menu group id (see config.vhd) of the menu item that is responsible
;       for triggering FILTER_FILES
; Output:
;   R8: 0=do not filter file, i.e. show file
FILTER_FILES    INCRB
                MOVE    R9, R0
        
                CMP     1, R9                   ; do not filter directories
                RBRA    _FFILES_RET_0, Z

                ; Context: Mount virtual drive
                CMP     CTX_MOUNT_DISKIMG, R10
                RBRA    _FFILES_1, !Z

                ; does this file have a supported disk-image extension?
                ; (.D64 for the 1541, .D81 for the 1581 -- intentionally NOT .G64,
                ; see doc/path-to-d81.md section 12)
                MOVE    C64_DISKIMG_EXT, R1     ; R1: 0-terminated table of ext ptrs
_FFILES_DIMG    MOVE    @R1++, R9               ; R9: next extension (0 = end of table)
                RBRA    _FFILES_DOFLT, Z        ; end of table reached: filter it
                RSUB    M2M$CHK_EXT, 1          ; preserves R8/R9/R10 (and our R1)
                RBRA    _FFILES_RET_0, C        ; extension matched: do not filter it
                RBRA    _FFILES_DIMG, 1         ; try the next extension

_FFILES_DOFLT   MOVE    1, R8                   ; no match: filter it
                RBRA    _FFILES_RET, 1

                ; Context: Load cartridge ROM file
_FFILES_1       CMP     CTX_LOAD_ROM, R10
                RBRA    _FFILES_RET_0, !Z       ; do not filter in other CTXs

                ; menu item "PRG:<Load>"
                CMP     C64_OPTM_G_LOAD_PRG, R11
                RBRA    _FFILES_2, !Z
                MOVE    C64_PRGFILE, R9
                RBRA    _FFILES_3, 1

                ; menu item "CRT:<Load>"
_FFILES_2       CMP     C64_OPTM_G_MOUNT_CRT, R11
                RBRA    _FFILES_RET_0, !Z
                MOVE    C64_CRTFILE, R9

                ; does this file have the right file extension?
_FFILES_3       RSUB    M2M$CHK_EXT, 1
                RBRA    _FFILES_DOFLT, !C       ; no: filter it

_FFILES_RET_0   XOR     R8, R8                  ; do not filter

_FFILES_RET     MOVE    R0, R9
                DECRB
                RET

; PREP_LOAD_IMAGE callback function:
;
; Some images need to be parsed, for example to extract configuration data or
; to move the file read pointer to the start position of the actual data.
; Sanity checks ("is this a valid file") can also be implemented here.
; Last but not least: The mount system supports the concept of a 2-bit
; "image type". In case this is used at the core of your choice, make sure
; you return the correct image type.
;
; Input:
;   R8: File handle: You are allowed to modify the read pointer of the handle
;   R9: Context (CTX_* constants in sysdef.asm)
;  R10: Menu group id (see config.vhd) of the menu item that is responsible
;       for triggering PREP_LOAD_IMAGE
; Output:
;   R8: 0=OK, error code otherwise
;   R9: image type if R8=0, otherwise 0 or optional ptr to error msg string
PREP_LOAD_IMAGE INCRB

                ; Context CRT/ROM loading
                CMP     CTX_LOAD_ROM, R9
                RBRA    _PREP_LI_START, !Z      ; not load-rom: disk-image path below

                ; A .crt cartridge is staged into the SIMCRT HyperRAM pool, which borders the
                ; D81 mount buffer (see C_HMAP_VD0 in globals.vhd). Reject an oversized .crt so
                ; it cannot stream past the pool into the disk-image staging area. .prg files
                ; and ROM images do not use that pool, so they pass through unchecked. The
                ; ceiling C64_CRT_MAX_SIZE_HI/LO is auto-generated by make_rom.sh from
                ; globals.vhd C_CRT_MAX_SIZE = (C_HMAP_VD0 - C_HMAP_CRT) * 8192, so it always
                ; tracks the HyperRAM map (no manual sync needed on a retune).
                CMP     C64_OPTM_G_MOUNT_CRT, R10
                RBRA    _PREP_LI_ROM_OK, !Z     ; not a .crt: accept (no size check)

                MOVE    R8, R0
                MOVE    R0, R1
                ADD     FAT32$FDH_SIZE_LO, R0
                MOVE    @R0, R0                 ; R0: file size low word
                ADD     FAT32$FDH_SIZE_HI, R1
                MOVE    @R1, R1                 ; R1: file size high word

                CMP     C64_CRT_MAX_SIZE_HI, R1 ; CMP X,Y: N <=> Y<X, Z <=> Y==X
                RBRA    _PREP_LI_ROM_OK, N      ; hi < max-hi  -> well under the limit
                RBRA    _PREP_LI_CRT_BIG, !Z    ; hi > max-hi  -> too big
                CMP     C64_CRT_MAX_SIZE_LO, R0 ; hi == max-hi: check the low word
                RBRA    _PREP_LI_ROM_OK, N      ; lo < max-lo  -> OK
                RBRA    _PREP_LI_ROM_OK, Z      ; lo == max-lo -> OK (exactly the limit)

_PREP_LI_CRT_BIG MOVE   1, R8                   ; lo > 0x6000 -> .crt too big
                MOVE    WRN_CRT_TOO_BIG, R9
                RBRA    _PREP_LI_RET, 1

_PREP_LI_ROM_OK XOR     R8, R8
                XOR     R9, R9
                RBRA    _PREP_LI_RET, 1

                ; Context is disk image loading: We check for valid disk
                ; image sizes as defined in D64_STDSIZE_L and D64_STDSIZE_H
_PREP_LI_START  MOVE    R8, R0
                MOVE    R0, R1

                ADD     FAT32$FDH_SIZE_LO, R0
                MOVE    @R0, R0                 ; R0: low word of file size
                ADD     FAT32$FDH_SIZE_HI, R1
                MOVE    @R1, R1                 ; R1: high word of file size

                ; check if the D64 filesize equals one of the valid variants
                MOVE    D64_VARIANT_CNT, R2     ; R2: amount of valid variants
                MOVE    D64_STDSIZE_L, R3       ; R3: table of valid lo words
                MOVE    D64_STDSIZE_H, R4       ; R4: table of valid hi words

_PREP_LI_CMP    MOVE    @R3++, R5               ; R5: valid lo word
                MOVE    @R4++, R6               ; R6: valid hi word

                CMP     R5, R0                  ; lo word equals table entry?
                RBRA    _PREP_LI_NEXT, !Z       ; no: check next variant
                CMP     R6, R1                  ; hi word equals table entry?
                RBRA    _PREP_LI_OK, Z          ; yes: correct filesize

_PREP_LI_NEXT   SUB     1, R2                   ; next variant
                RBRA    _PREP_LI_CMP, !Z

                ; not a valid D64: is it a valid D81 (exactly 819200 bytes)?
                ; 819200 decimal = 0x000C8000 hex (lo word 0x8000, hi word 0x000C).
                ; Only this exact size is accepted -- error-info variants (e.g. 822400
                ; bytes) would feed the 1581 a wrong geometry, so they are rejected.
                CMP     0x8000, R0              ; D81: low word matches?
                RBRA    _PREP_LI_WRONG, !Z      ; no: wrong size
                CMP     0x000C, R1              ; D81: high word matches?
                RBRA    _PREP_LI_WRONG, !Z      ; no: wrong size
                XOR     R8, R8                  ; no errors
                MOVE    C64_IMGTYPE_D81, R9     ; image type: D81 (1581)
                RBRA    _PREP_LI_RET, 1

                ; filesize wrong (neither a valid D64 nor a valid D81)
_PREP_LI_WRONG  MOVE    1, R8                   ; R8: error code
                MOVE    WRN_WRONG_IMG, R9       ; R9: error message (names D64 + D81)
                RBRA    _PREP_LI_RET, 1

                ; filesize correct (valid D64)
_PREP_LI_OK     XOR     R8, R8                  ; no errors
                MOVE    C64_IMGTYPE_D64, R9     ; image type: D64 (1541)

_PREP_LI_RET    DECRB
                RET

; ----------------------------------------------------------------------------
; Core specific callback functions: Custom tasks
; ----------------------------------------------------------------------------

; PREP_START callback function:
;
; Called right before the core is being started. At this point, the core
; is ready to run, settings are loaded (if the core uses settings) and the
; core is still held in reset (if RESET_KEEP is on). So at this point in time,
; you can execute tasks that change the run-state of the core.
;
; Input: None
; Output:
;   R8: 0=OK, else pointer to string with error message
;   R9: 0=OK, else error code
PREP_START      INCRB

                ; Apply the saved HDMI Filter selection. At this point the
                ; framework has already loaded its own default into the
                ; ascal polyphase RAM (LANCZOS2_12 + SCAN_BR_110_80 via
                ; M2M/rom/filters.asm:LOAD_ASCAL_FLT), and HELP_MENU_INIT has
                ; populated M2M$CFM_DATA from the saved SD config. We now
                ; overwrite the framework default with whatever the user
                ; chose -- before the core un-resets and the first frame
                ; reaches HDMI, so no glitch is visible. The default
                ; selection in config.vhd is "Scanlines", which loads the
                ; same pair as the framework default, so first-time users
                ; (or anyone with an empty config) see the V1 CRT-emulation
                ; look bit-identically.
                RSUB    LOAD_HDMI_FILTER, 1

                ; ------------------------------------------------------------
                ; JiffyDOS gate plus debug-console status report
                ; ------------------------------------------------------------
                ; JiffyDOS needs a JiffyDOS C64 Kernal (jd-c64.bin) plus at
                ; least one JiffyDOS drive DOS: the 1541 (jd-c1541.bin) and/or
                ; the 1581 (jd-c1581.bin). All three are optional auto-load ROMs
                ; (globals.vhd); CRTROM_AUT_LDF[i] is 1 when ROM i has loaded:
                ;   [0] = jd-c64    [1] = jd-c1541    [2] = jd-c1581
                ;
                ; When JiffyDOS is the selected Kernal we print a per-component
                ; status block to the debug console and then keep JiffyDOS if
                ; jd-c64 AND (jd-c1541 OR jd-c1581) loaded. Otherwise we revert
                ; the LIVE Kernal to Standard for this session only. A missing
                ; drive ROM degrades to its standard DOS (the 1541 and 1581
                ; custom ROM slots are INITFILEd with the stock DOS), so every
                ; ROM combination still boots a working C64 and a working drive.
                ;
                ; M2M$SET_SETTING writes only the in-memory M2M$CFM_DATA mirror,
                ; not the SD config file (tools.asm), so the saved JiffyDOS
                ; preference survives a transient missing-ROM boot.
                MOVE    C64_OSM_KERNAL_JIFFY, R8
                RSUB    M2M$GET_SETTING, 1      ; is JiffyDOS the selected Kernal?
                CMP     1, R9
                RBRA    PREP_START_R, !Z        ; no -> nothing to gate, stay silent

                MOVE    JDS_HEADER, R8          ; "JiffyDOS status:"
                SYSCALL(puts, 1)

                ; C64 Kernal component line plus the jd-c64 gate
                MOVE    CRTROM_AUT_LDF, R0      ; R0 -> CRTROM_AUT_LDF base
                MOVE    JDS_L_C64, R8           ; label "  C64 Kernal: "
                MOVE    @R0, R9                 ; R9 = LDF[0] (jd-c64)
                MOVE    JDS_F_C64, R10          ; basename "c64"
                RSUB    _JD_RPT_LINE, 1
                CMP     0, @R0                  ; jd-c64 loaded?
                RBRA    _JD_HAVE_C64, !Z        ; yes -> report the drive ROMs
                MOVE    JDS_R_NOC64, R8         ; no -> reason "no JiffyDOS C64 Kernal"
                RBRA    _JD_REVERT, 1

                ; 1541 component line (R1 keeps LDF[1] for the drive gate below)
_JD_HAVE_C64    MOVE    CRTROM_AUT_LDF, R0
                ADD     1, R0                   ; R0 -> LDF[1] (jd-c1541)
                MOVE    JDS_L_1541, R8          ; label "  1541 DOS  : "
                MOVE    @R0, R9                 ; R9 = LDF[1]
                MOVE    JDS_F_1541, R10         ; basename "c1541"
                RSUB    _JD_RPT_LINE, 1
                MOVE    @R0, R1                 ; R1 = LDF[1]

                ; 1581 component line (accumulate LDF[2] into R1)
                MOVE    CRTROM_AUT_LDF, R0
                ADD     2, R0                   ; R0 -> LDF[2] (jd-c1581)
                MOVE    JDS_L_1581, R8          ; label "  1581 DOS  : "
                MOVE    @R0, R9                 ; R9 = LDF[2]
                MOVE    JDS_F_1581, R10         ; basename "c1581"
                RSUB    _JD_RPT_LINE, 1
                ADD     @R0, R1                 ; R1 = LDF[1] + LDF[2]

                CMP     0, R1                   ; at least one drive ROM present?
                RBRA    _JD_NODRV, Z            ; none -> revert (no drive benefit)
                MOVE    JDS_V_ACTIVE, R8        ; "  -> JiffyDOS active"
                SYSCALL(puts, 1)
                RBRA    PREP_START_R, 1

_JD_NODRV       MOVE    JDS_R_NODRV, R8         ; reason "no drive ROM"

                ; revert: print the disabled verdict (PRE + reason + SUF, shared
                ; by both revert paths) then clear the live JiffyDOS bit and set
                ; Standard.
_JD_REVERT      MOVE    R8, R0                  ; R0 = reason string
                MOVE    JDS_V_DIS_PRE, R8       ; "  -> JiffyDOS disabled ("
                SYSCALL(puts, 1)
                MOVE    R0, R8                  ; reason
                SYSCALL(puts, 1)
                MOVE    JDS_V_DIS_SUF, R8       ; "), using standard Kernal"
                SYSCALL(puts, 1)
                MOVE    C64_OSM_KERNAL_JIFFY, R8
                XOR     R9, R9
                RSUB    M2M$SET_SETTING, 1      ; clear the JiffyDOS bit
                MOVE    C64_OSM_KERNAL_STD, R8
                MOVE    1, R9
                RSUB    M2M$SET_SETTING, 1      ; set the Standard bit

PREP_START_R    XOR     R8, R8
                XOR     R9, R9

                DECRB
                RET

; _JD_RPT_LINE helper (for the PREP_START JiffyDOS status report):
;
; Print one component status line. The three lines share the "JiffyDOS" and
; "standard (jd-...not found)" fragments through this helper instead of storing
; one full string per component, which keeps the report cheap in ROM.
;
; Input:  R8  = label string, e.g. "  C64 Kernal: "
;         R9  = load flag (0 = ROM not loaded, else loaded)
;         R10 = ROM file basename ("c64" / "c1541" / "c1581"); printed only when
;               R9 = 0, spliced between "standard (jd-" and ".bin not found)"
; Output: none; R0..R7 and R9..R12 preserved (R8 is clobbered)
_JD_RPT_LINE    INCRB
                MOVE    R9, R0                  ; R0 = load flag
                MOVE    R10, R1                 ; R1 = file basename
                SYSCALL(puts, 1)                ; R8 is the label: print it
                CMP     0, R0                   ; ROM loaded?
                RBRA    _JD_RPT_STD, Z          ; no -> "standard (jd-<name>...)"
                MOVE    JDS_V_JIFFY, R8         ; "JiffyDOS"
                SYSCALL(puts, 1)
                RBRA    _JD_RPT_RET, 1
_JD_RPT_STD     MOVE    JDS_STD_PRE, R8         ; "standard (jd-"
                SYSCALL(puts, 1)
                MOVE    R1, R8                  ; "c64" / "c1541" / "c1581"
                SYSCALL(puts, 1)
                MOVE    JDS_STD_SUF, R8         ; ".bin not found)"
                SYSCALL(puts, 1)
_JD_RPT_RET     DECRB
                RET

; RESET_CORE helper:
;
; Pulses M2M$CSR bit 0 ("Reset the MiSTer core") long enough to satisfy the
; 32-cycle minimum at reset_soft_i (see RESET SEMANTICS in main.vhd).
; A bare OR/AND pair would only be a few QNICE cycles wide and, after the
; 2-stage CDC in framework.vhd, fall short of that floor. The delay loop
; widens the pulse to >= 64 main_clk cycles, comfortably above the limit.
;
; Semantics: M2M$CSR_RESET is a strict subset of a short MEGA65 reset-button
; press: soft-reset the C64 only, no AV-pipeline / HyperRAM touch, no cart
; eject. To exit a cart, hold the MEGA65 reset button for at least 1.5 s.
;
; Input:  none
; Output: none (callers do their own R8/R9 = 0/0 if needed)
RESET_CORE      INCRB
                MOVE    M2M$CSR, R0
                OR      M2M$CSR_RESET, @R0      ; assert soft reset
                MOVE    64, R1                  ; widen pulse to >=32 main_clk
_RC_DELAY       SUB     1, R1                   ; cycles after the 2-FF CDC
                RBRA    _RC_DELAY, !Z
                AND     M2M$CSR_UN_RESET, @R0   ; release soft reset
                DECRB
                RET

; OSM_SEL_POST callback function:
;
; Called each time the user selects something in the on-screen-menu (OSM),
; and while the OSM is still visible. This means, that this callback function
; is called on each press of one of the valid selection keys with the
; exception that pressing a selection key while hovering over a submenu entry
; or exit point does not call this function. All the functionality and
; semantics associated with a certain menu item is already handled by the
; framework when OSM_SELECTED is called, so you are not able to change the
; basic semantics but you are able to add core specific additional
; "intelligent" semantics and behaviors.
;
; Input:
;   R8: selected menu group (as defined in config.vhd)
;   R9: selected item within menu group
;       in case of single selected items: 0=not selected, 1=selected
;   R10: OPTM_KEY_SELECT (by default means "Return") or
;        OPTM_KEY_SELALT (by default means "Space")
; Output:
;   R8: 0=OK, else pointer to string with error message
;   R9: 0=OK, else error code
OSM_SEL_POST    INCRB

                ; HDMI Filter selection changed: re-push the matching (H, V)
                ; coefficient pair into the ascal polyphase RAM. NO core
                ; reset -- only the coefficient RAM content changes; the C64
                ; keeps running. The user sees the new filter from the next
                ; frame.
                CMP     C64_OPTM_G_HDMI_FILTER, R8
                RBRA    _OSM_SP_FILTER, Z

                ; Auto-soft-reset the core when the user changes a setting
                ; that requires a clean restart:
                ;   * Kernal mode
                ;   * Expansion port mode (HW slot vs. simulated cartridge)
                ;   * Simulated 1750 REU
                ;
                ; This is a soft reset (M2M$CSR_RESET is a strict subset of
                ; a short MEGA65 reset-button press), so a loaded cartridge
                ; persists and re-autostarts after the reset. To exit a
                ; cart, hold the MEGA65 reset button for at least 1.5 s.
                CMP     C64_OPTM_G_KERNAL_MODES, R8
                RBRA    _OSM_SP_RESET, Z
                CMP     C64_OPTM_G_EXP_PORT, R8
                RBRA    _OSM_SP_RESET, Z
                CMP     C64_OPTM_G_REU, R8
                RBRA    _OSM_SP_RESET, Z
                RBRA    _OSM_SEL_POST_R, 1

_OSM_SP_FILTER  RSUB    LOAD_HDMI_FILTER, 1
                RBRA    _OSM_SEL_POST_R, 1

_OSM_SP_RESET   RSUB    RESET_CORE, 1

_OSM_SEL_POST_R XOR     R8, R8
                XOR     R9, R9

                DECRB
                RET

; Physical internal 1581 read-only diagnostic device (issue #90). Its device id
; is C_DEV_C64_PHYS1581 = 0x0108 (globals.vhd) and physical_1581_diag.vhd exposes
; the live controller state at word offset RM_CTRL_STATE = 0x04. That word is
; nonzero in the read-FSM phase (bits 15..12), the step-FSM phase (bits 11..10)
; or the motor-on bit (bit 3) while, and only while, the physical drive is
; actually accessing the medium: all three are held at 0 whenever drive 8 is
; backed by a disk image (the controller resets its FSMs and clears motor-on
; when it is not in physical mode). So P1581_BUSY_MASK is a clean physical-drive
; busy flag that is meaningful without any extra RTL and naturally reads idle in
; disk-image mode. Read via the standard M2M$RAMROM_DEV / _4KWIN / _DATA window.
P1581_DIAG_DEV  .EQU    0x0108                  ; C_DEV_C64_PHYS1581
P1581_RM_CTRL   .EQU    0x0004                  ; RM_CTRL_STATE word offset
P1581_BUSY_MASK .EQU    0xFC08                  ; read-phase | step-phase | motor

; OSM_SEL_PRE callback function:
;
; Identical to the OSM_SEL_POST callback function (see above) but it is being
; called before the functionality and semantics associated with a certain
; menu item has been handled by the framework.
OSM_SEL_PRE     INCRB

                ; Idle-gate for "Use internal 1581" (issue #90): ignore an
                ; attempt to switch drive 8 between disk image and the physical
                ; internal 1581 while that physical drive is mid-access. The
                ; handler is _OSM_PRE_1581, at the end of this callback.
                CMP     C64_OPTM_G_INT1581, R8
                RBRA    _OSM_PRE_1581, Z

                ; Automatically switch to "Simulate cartridge" if the user
                ; chooses to load a software cartridge. When the previous
                ; mode was "Use hardware slot" we additionally soft-reset
                ; the core: otherwise the running C64 would see the HW
                ; expansion port silently disappear under it and stay hung
                ; while the file selector is open. The sw_cartridge_wrapper
                ; will issue its own reset once the .crt has been loaded.
                CMP     C64_OPTM_G_MOUNT_CRT, R8
                RBRA    _OSM_SEL_PRE_R, !Z
                MOVE    C64_OSM_SIM_CRT, R8
                RSUB    M2M$GET_SETTING, 1
                CMP     1, R9                   ; already in sim crt mode?
                RBRA    _OSM_SEL_PRE_R, Z       ; yes, then nothing to do
                MOVE    1, R9                   ; no, then set sim crt mode
                RSUB    M2M$FORCE_MENU, 1
                RSUB    RESET_CORE, 1           ; HW slot just decoupled;
                                                ; park the C64 in clean reset
                RBRA    _OSM_SEL_PRE_R, 1       ; do not fall into _OSM_PRE_1581

                ; Idle-gate handler for OPTM_G_INT1581. On entry R9 holds the
                ; requested new single-select value (1 = internal 1581,
                ; 0 = disk image). menu.asm has already flipped the on-screen
                ; marker and the OPTM_IR_STDSEL heap, but the OSM bit that
                ; main.vhd turns into phys_1581_en is only written by the
                ; framework AFTER this callback returns (the OPTM_IR_STDSEL ->
                ; M2M$CFM_DATA copy in OPTM_CB_SEL). So a revert done here is
                ; still in time to keep the hardware bit unchanged.
                ;
                ; Read the physical-1581 control-state word: if the drive is
                ; idle (mask = 0) let the framework apply the change; if it is
                ; busy, force the item back to its previous value. M2M$FORCE_MENU
                ; both repaints the marker and rewrites M2M$CFM_DATA, and the
                ; framework then re-copies the (reverted) OPTM_IR_STDSEL over the
                ; same bit, so neither the menu nor the core ever sees the flip.
                ; Note this only ever fires when switching AWAY from a spinning
                ; internal 1581 (turning it OFF): in disk-image mode the physical
                ; drive is idle by construction, so turning it ON is never gated.
_OSM_PRE_1581   MOVE    R9, R0                  ; R0: the requested new value
                MOVE    M2M$RAMROM_DEV, R1
                MOVE    P1581_DIAG_DEV, @R1     ; select the diag device
                MOVE    M2M$RAMROM_4KWIN, R1
                MOVE    0, @R1                   ; register-bank window 0
                MOVE    M2M$RAMROM_DATA, R1
                ADD     P1581_RM_CTRL, R1        ; -> RM_CTRL_STATE
                MOVE    @R1, R1                  ; R1: control-state word
                AND     P1581_BUSY_MASK, R1      ; read / step / motor active?
                RBRA    _OSM_SEL_PRE_R, Z        ; idle: allow the change

                MOVE    C64_OSM_INTERNAL_1581, R8 ; busy: revert to old value
                MOVE    1, R9                     ; single-select toggle, so the
                SUB     R0, R9                    ; previous value is 1 - new
                RSUB    M2M$FORCE_MENU, 1
                RBRA    _OSM_SEL_PRE_R, 1

_OSM_SEL_PRE_R  XOR     R8, R8
                XOR     R9, R9

                DECRB
                RET

; ----------------------------------------------------------------------------
; Core specific callback functions: Custom messages
; ----------------------------------------------------------------------------

; CUSTOM_MSG callback function:
;
; Called in various situations where the Shell needs to output a message
; to the end user. The situations and contexts are described in sysdef.asm
;
; Input:
;   R8: Situation (CMSG_* constants in sysdef.asm)
;   R9: Context   (CTX_* constants in sysdef.asm)
; Output:
;   R8: 0=no custom message available, otherwise pointer to string

CUSTOM_MSG      INCRB
                MOVE    R8, R0
                XOR     R8, R8                  ; no custom message

                CMP     CMSG_BROWSENOTHING, R0  ; "no D64" situation?
                RBRA    _CUSTOM_MSG_RET, !Z     ; no: default custom message
                CMP     CTX_MOUNT_DISKIMG, R9   ; trying to mount a disk?
                RBRA    _CUSTOM_MSG_RET, !Z     ; no: default custom message
                MOVE    WRN_NO_D64, R8          ; yes: custom message

_CUSTOM_MSG_RET DECRB
                RET

; ----------------------------------------------------------------------------
; Core specific constants and strings
; ----------------------------------------------------------------------------

; auto-generated file that constains the menu indexes from mega65.vhd
#include "osm_const.asm"

; Warning: We only support exact-size standard D64 and D81 images
WRN_WRONG_IMG   .ASCII_P "\n\nA D64 disk image must be exactly 174848\n"
                .ASCII_P "bytes (35 tracks) or 196608 bytes (40\n"
                .ASCII_P "tracks). A D81 must be exactly 819200 bytes\n"
                .ASCII_P "(error-info variants are not supported)."
                .ASCII_W "\n\nPress SPACE to continue.\n"

; Warning: the .crt file is larger than the SIMCRT HyperRAM pool
WRN_CRT_TOO_BIG .ASCII_P "\n\nThis .crt file is too large: it does not\n"
                .ASCII_P "fit into the simulated-cartridge memory pool."
                .ASCII_W "\n\nPress SPACE to continue.\n"

; Warning: Nothing to browse
WRN_NO_D64      .ASCII_P "This core uses D64 and D81 disk images.\n\n"
                .ASCII_P "Please copy at least one D64 or D81 file\n"
                .ASCII_P "to any sub-directory or to the root\n"
                .ASCII_P "directory of this SD card.\n\n"
                .ASCII_P "If you use a folder called /c64, then\n"
                .ASCII_P "the file browser will always start there.\n\n"
                .ASCII_P "You can use long file names and you can\n"
                .ASCII_P "also use nested sub-directories to nicely\n"
                .ASCII_P "order your collection of disk images.\n\n"
                .ASCII_P "Nothing to browse.\n\n"
                .ASCII_W "Press Space to continue."

; JiffyDOS status report, printed to the debug console by PREP_START when
; JiffyDOS is the selected Kernal. The component value ("JiffyDOS") and the
; "standard (jd-<name>.bin not found)" fragments are shared by _JD_RPT_LINE
; across all three lines; the two revert verdicts share PRE and SUF. This keeps
; the report cheaper in ROM than one full string per case.
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

; On-screen "Kernal: %s" summary tags built by SUBMENU_SUMMARY (_SS_TRY_KERNAL).
; The single-drive cases reuse the " JiffyDOS" menu label for the word itself,
; so only the drive tags and the compact both-drives form cost ROM here. The
; both-drives form is shortened to "Jiffy 1541+1581" (15 chars) so the rendered
; line " Kernal: Jiffy 1541+1581" (24) fits the 25-column OSM width clamp; the
; full "JiffyDOS 1541+1581" would be 27 and get truncated.
SS_K_BOTH       .ASCII_W "Jiffy 1541+1581"
SS_KT_1541      .ASCII_W " 1541"
SS_KT_1581      .ASCII_W " 1581"

; C64 specific file extensions (need to be upper case)
C64_IMGFILE_D64 .ASCII_W ".D64"
C64_IMGFILE_G64 .ASCII_W ".G64"
C64_IMGFILE_D81 .ASCII_W ".D81"
C64_CRTFILE     .ASCII_W ".CRT"
C64_PRGFILE     .ASCII_W ".PRG"

; Table of the disk-image extensions the file browser shows in the mount-drive
; context (0-terminated). Intentionally excludes .G64 (1541 real-GCR, out of
; scope -- see doc/path-to-d81.md section 12).
C64_DISKIMG_EXT .DW     C64_IMGFILE_D64, C64_IMGFILE_D81, 0

; C64 disk image types
C64_IMGTYPE_D64 .EQU    0x0000  ; 1541 emulated GCR: D64
C64_IMGTYPE_G64 .EQU    0x0001  ; 1541 real GCR mode: G64, D64
C64_IMGTYPE_D81 .EQU    0x0002  ; 1581: D81

; We currently only support D64 images with 35 tracks (filesize 174,848 bytes)
; or 40 tracks (filesize 196,608 bytes).
; 174848 decimal = 0x0002AB00 hex
; 196608 decimal = 0x00030000 hex
D64_VARIANT_CNT .EQU    2
D64_STDSIZE_L   .DW     0xAB00, 0x0000
D64_STDSIZE_H   .DW     0x0002, 0x0003

; ----------------------------------------------------------------------------
; HDMI Filter dispatch
; ----------------------------------------------------------------------------

; LOAD_HDMI_FILTER: Read the saved HDMI Filter selection from M2M$CFM_DATA
; and configure ascal accordingly. Called from PREP_START (boot) and
; OSM_SEL_POST (runtime). Eight options, single-select: exactly one of the
; C64_OSM_HDMI_FLT_* bits is set at any time -- OPTM_G_STDSEL in config.vhd
; guarantees a default ("Scanlines") if the saved SD config file is missing
; or empty.
;
; Two execution shapes, both encoded in HDMI_FLT_TABLE rows
; (OSM_bit, ASCAL_MODE_word, H_label, V_label):
;
;   * Native modes (No Filter / Sharp Bilinear / Bicubic) -> write the
;                  matching mode word (NEAREST / SBILINEAR / BICUBIC) to
;                  M2M$ASCAL_MODE. The H/V labels are 0 sentinels: we skip
;                  the polyphase RAM write entirely and let ascal run its
;                  built-in scaler datapath.
;   * Polyphase modes (Smooth / Lanczos / Scanlines / CRT (S-Video) /
;                  CRT (Composite)) -> write POLYPHASE then push the
;                  (H_label, V_label) pair into the ascal polyphase RAM
;                  via M2M$LOAD_POLYPHASE.
;
; This routine assumes ASCAL_USAGE=1 (AUSE_CUSTOM) in config.vhd, which
; tells ASCAL_INIT to clear M2M$CSR bit 11 and leave M2M$ASCAL_MODE
; writable. If a future core sets ASCAL_USAGE back to 2 (AUSE_AUTO), the
; mode writes below silently no-op.
;
; Input:  None
; Output: R8 = 0, R9 = 0 on success
LOAD_HDMI_FILTER INCRB
                MOVE    HDMI_FLT_TABLE, R0
                MOVE    8, R1                   ; option count

_LHF_LOOP       MOVE    @R0++, R8               ; R8 = OSM bit for this option
                RSUB    M2M$GET_SETTING, 1
                CMP     1, R9                   ; selected?
                RBRA    _LHF_FOUND, Z           ; yes -> apply this row
                ADD     3, R0                   ; no -> skip MODE, H, V
                SUB     1, R1
                RBRA    _LHF_LOOP, !Z

                ; Defensive fallback: no bit set. Force Scanlines preset
                ; (polyphase mode + Lanczos2_12 / Scan_Br_110_80).
                MOVE    M2M$ASCAL_MODE, R2
                MOVE    M2M$ASCAL_POLYPHASE, @R2
                MOVE    LANCZOS2_12,    R8
                MOVE    SCAN_BR_110_80, R9
                RSUB    M2M$LOAD_POLYPHASE, 1
                RBRA    _LHF_RET, 1

_LHF_FOUND      MOVE    @R0++, R3               ; R3 = ASCAL_MODE word
                MOVE    M2M$ASCAL_MODE, R2
                MOVE    R3, @R2                 ; write mode register
                MOVE    @R0++, R8               ; R8 = H label (0 = sentinel)
                MOVE    @R0,   R9               ; R9 = V label (0 = sentinel)
                CMP     0, R8                   ; native-mode sentinel?
                RBRA    _LHF_RET, Z             ; yes -> done, no RAM write
                RSUB    M2M$LOAD_POLYPHASE, 1

_LHF_RET        XOR     R8, R8
                XOR     R9, R9
                DECRB
                RET

; Filter table: (OSM_bit, ASCAL_MODE_word, H_label, V_label) per option, in
; OPTM_ITEMS display order. The first three rows use ascal native modes
; (NEAREST / SBILINEAR / BICUBIC); their H and V are 0 sentinels so the
; dispatcher skips the polyphase RAM write for them. The remaining five
; rows all select polyphase (mode 100) and provide real coefficient table
; labels.
;
; See M2M/video_filters/README.md for per-blob perceptual notes and
; CORE/vhdl/config.vhd for the OPTM_ITEMS / OPTM_GROUPS structure.
HDMI_FLT_TABLE  .DW C64_OSM_HDMI_FLT_NO_FILTER,     M2M$ASCAL_NEAREST,   0,                   0
                .DW C64_OSM_HDMI_FLT_SHARP,         M2M$ASCAL_SBILINEAR, 0,                   0
                .DW C64_OSM_HDMI_FLT_BICUBIC,       M2M$ASCAL_BICUBIC,   0,                   0
                .DW C64_OSM_HDMI_FLT_SMOOTH,        M2M$ASCAL_POLYPHASE, GS_SHARPNESS_050,    GS_SHARPNESS_050
                .DW C64_OSM_HDMI_FLT_LANCZOS,       M2M$ASCAL_POLYPHASE, LANCZOS2_12,         LANCZOS2_12
                .DW C64_OSM_HDMI_FLT_SCANLINES,     M2M$ASCAL_POLYPHASE, LANCZOS2_12,         SCAN_BR_110_80

                ; As long as we are not supporting the full filter and
                ; post-processing chain of MiSTer:
                ;
                ; Both CRT rows reuse SCAN_BR_110_80 as the V file (same as
                ; Scanlines mode). CRT_Sim_*_V is a deep ~40% mid-phase plateau
                ; designed to be combined with the MiSTer gamma LUT + shadow mask;
                ; M2M V2.1 supports neither, so standalone the plateau crushes
                ; bright C64 content into a dark band. The Composite vs S-Video
                ; character lives entirely in the H file (Composite has heavy
                ; horizontal blur, S-Video has mild softening), so swapping only
                ; the V file preserves the perceptual distinction while restoring
                ; near-unity mean brightness.
                .DW C64_OSM_HDMI_FLT_CRT_SVIDEO,    M2M$ASCAL_POLYPHASE, CRT_SIM_SVIDEO_H,    SCAN_BR_110_80
                .DW C64_OSM_HDMI_FLT_CRT_COMPOSITE, M2M$ASCAL_POLYPHASE, CRT_SIM_COMPOSITE_H, SCAN_BR_110_80

; Filter coefficient blobs for the 5 polyphase-based options. LANCZOS2_12 and
; SCAN_BR_110_80 are already linked via the M2M framework file
; M2M/rom/filters.asm (included from M2M/rom/shell.asm).
#include "../../M2M/video_filters/GS_Sharpness_050.asm"
#include "../../M2M/video_filters/CRT_Sim_Composite_H.asm"
#include "../../M2M/video_filters/CRT_Sim_SVideo_H.asm"

; This needs to be the last thing before the "Variables" sections starts
END_OF_ROM      .DW 0

; ----------------------------------------------------------------------------
; Variables: Need to be located in RAM
; ----------------------------------------------------------------------------

#ifdef RELEASE
                .ORG    0x8000                  ; RAM starts at 0x8000
#endif

; M2M shell variables
#include "../../M2M/rom/shell_vars.asm"

; Scratch buffers for the custom SUBMENU_SUMMARY ("Model: %s") callback above.
; They are written and consumed within a single OPTM_SHOW pass (the line is
; drawn immediately after the callback returns), so a single static set is safe.
SS_VALUE_LEN    .EQU 24                         ; capacity of SS_VALUE (words)
SS_LINE_LEN     .EQU 32                         ; capacity of SS_LINE (words)
SS_VALUE        .BLOCK SS_VALUE_LEN             ; built %s value, e.g. "PAL C128 2x"
SS_LINE         .BLOCK SS_LINE_LEN              ; full custom line "Model: PAL C128 2x"

; ----------------------------------------------------------------------------
; Heap and Stack: Need to be located in RAM after the variables
; ----------------------------------------------------------------------------

; The On-Screen-Menu uses the heap for several data structures. This heap
; is located before the main system heap in memory.
; You need to deduct MENU_HEAP_SIZE from the actual heap size below.
; Example: If your HEAP_SIZE would be 30208, then you write 30208-3072=27136
; instead, but when doing the sanity check calculations, you use 30208
;
; 3072 words fit the V6 (#189) menu: 159 items, 10 submenus, 1570 character
; OPTM_ITEMS string -> budget 1 = 2068 words, budget 2 = 14 x 27 = 378 words
; (see LOG_HEAP1/LOG_HEAP2 on the serial console for the live numbers), plus
; headroom for the planned per-item dependency array (#229) and label growth
MENU_HEAP_SIZE  .EQU 3072

#ifndef RELEASE

; heap for storing the sorted structure of the current directory entries
; this needs to be the last variable before the monitor variables as it is
; only defined as "BLOCK 1" to avoid a large amount of null-values in
; the ROM file
HEAP_SIZE       .EQU 4096                       ; 7168 - 3072 = 4096
HEAP            .BLOCK 1

; in RELEASE mode: 26.5k of heap which leads to a better user experience
; when it comes to folders with a lot of files
#else

HEAP_SIZE       .EQU 27136                      ; 30208 - 3072 = 27136
HEAP            .BLOCK 1
 
; The monitor variables use 22 words, round to 32 for being safe and subtract
; it from FF00 because this is at the moment the highest address that we
; can use as RAM: 0xFEE0
; The stack starts at 0xFEE0 (search var VAR$STACK_START in m2m-rom.lis to
; calculate the address). To see, if there is enough room for the stack
; given the HEAP_SIZE do this calculation: Add 30208 words to HEAP which
; is currently 0x8220 (the SS_VALUE/SS_LINE buffers above sit just before it)
; and subtract the result from 0xFEE0. This yields currently a stack size of
; 1728, which is more than 1.5k words, and therefore sufficient for this program.

                .ORG    0xFEE0                  ; @TODO: automate calculation
#endif

; STACK_SIZE: Size of the global stack and should be a minimum of 768 words
; after you subtract B_STACK_SIZE.
; B_STACK_SIZE: Size of local stack of the the file- and directory browser. It
; should also have a minimum size of 768 words. If you are not using the
; Shell, then B_STACK_SIZE is not used.
STACK_SIZE      .EQU    1536
B_STACK_SIZE    .EQU    768

#include "../../M2M/rom/main_vars.asm"
