; ****************************************************************************
; MiSTer2MEGA65 (M2M) QNICE ROM
;
; Virtual Drives
;
; Drive mounting logic according to MiSTers "SD" interface (see vdrives.vhd).
; The file vdrives.asm needs the environment of shell.asm.
;
; done by sy2002 in 2022 and licensed under GPL v3
; ****************************************************************************

; ----------------------------------------------------------------------------
; Initialize library
; ----------------------------------------------------------------------------

; use the sysinfo device to initialize the vdrives system:
; get the amount of virtual drives, the device id of the vdrives.vhd device
; and an array of RAM buffers for the disk images
VD_INIT         SYSCALL(enter, 1)

                ; HANDLE_MOUNTING: no direct mode, nothing preselected and no
                ; remembered folders for VD_NEXT_DISK (consecutive variables)
                XOR     R2, R2                  ; R2: zero
                MOVE    OPTM_DIRECT, R1
                MOVE    R2, @R1++               ; OPTM_DIRECT
                MOVE    R2, @R1++               ; HM_PRESELECT
                MOVE    R2, @R1++               ; VD_SDGEN

                ; initialize the double-indirectly located file handles for
                ; the virtual drive system and VD_NXT_INFO
                MOVE    HNDL_VD_FILES, R8
                MOVE    VDRIVES_MAX, R9
_VDI_L1         MOVE    @R8++, R0               ; double indirection leads..
                MOVE    R2, @R0                 ; to the data of the file hdl
                MOVE    R2, @R1++               ; VD_NXT_INFO: 4 words/drive
                MOVE    R2, @R1++
                MOVE    R2, @R1++
                MOVE    R2, @R1++
                SUB     1, R9
                RBRA    _VDI_L1, !Z

                ; make sure to initialize also in case of zero vdrives
                MOVE    OPTM_MNT_STATUS, R8
                MOVE    0, @R8
                MOVE    OPTM_DTY_STATUS, R8
                MOVE    0, @R8

                ; copy data from globals.vhd
                MOVE    M2M$RAMROM_DEV, R8
                MOVE    M2M$SYS_INFO, @R8
                MOVE    M2M$RAMROM_4KWIN, R8
                MOVE    M2M$SYS_VDRIVES, @R8
                MOVE    VD_NUM, R8
                MOVE    VDRIVES_NUM, R0         ; number of virtual drives
                MOVE    @R8, @R0
                MOVE    @R0, R0
                MOVE    R0, R7                  ; R7: remember # of vdrives
                MOVE    VDRIVES_MAX, R1
                CMP     R0, R1                  ; vdrives > maximum?
                RBRA    _START_VD, !N           ; no: continue

                MOVE    ERR_FATAL_VDMAX, R8     ; yes: stop core
                MOVE    R0, R9
                RBRA    FATAL, 1

_START_VD       MOVE    VD_DEVICE, R1           ; device id of vdrives.vhd
                MOVE    VDRIVES_DEVICE, R2
                MOVE    @R1, @R2

                CMP     0, R0                   ; no vdrives at all?
                RBRA    _VDI_RET, Z             ; yes: skip the rest

                ; ------------------------------------------------------------
                ; Initializations that are only relevant, if we have at 
                ; least one vdrive
                ; ------------------------------------------------------------

                XOR     R1, R1                  ; loop var for buffer array
                MOVE    VD_RAM_BUFFERS, R2      ; Source data from config.vhd
                MOVE    VDRIVES_BUFS, R3        ; Dest. buf. in shell_vars.asm

_START_VD_CPY_1 MOVE    @R2++, @R3

                RBRA    _START_VD_CPY_F, Z      ; illegal values for buffer..
                CMP     0xEEEE, @R3++           ; ..ptrs indicate that there..
                RBRA    _START_VD_CPY_2, !Z     ; ..are not enough of them:
_START_VD_CPY_F MOVE    ERR_FATAL_VDBUF, R8     ; stop core
                XOR     R9, R9
                RBRA    FATAL, 1

_START_VD_CPY_2 ADD     1, R1
                CMP     R0, R1
                RBRA    _START_VD_CPY_1, !Z

                ; remember current mount status
                RSUB    VD_MNT_ST_SET, 1

                ; retrieve anti-trashing-delay from config.vhd and store
                ; it to the appropriate vdrives register for each drive
                ; @TODO: potential for more flexibility see config.vhd
                MOVE    R7, R6                  ; R6: remember drive count
                MOVE    M2M$RAMROM_DEV, R8
                MOVE    M2M$CONFIG, @R8
                MOVE    M2M$RAMROM_4KWIN, R8
                MOVE    M2M$CFG_GENERAL, @R8
                MOVE    M2M$CFG_VD_AT_DELAY, R8
                MOVE    @R8, R0                 ; R0: anti-trashing-delay
_START_VD_LP1   SUB     1, R7                   ; walk backwards through drvs
                MOVE    R7, R8
                MOVE    VD_CACHE_FLUSH_DE, R9
                MOVE    R0, R10
                RSUB    VD_DRV_WRITE, 1
                CMP     0, R7
                RBRA    _START_VD_LP1, !Z

                ; retrieve amount of bytes saved in one iteration of the 
                ; background saving (buffer flushing) process
                ; @TODO: similar as above; see config.vhd
                MOVE    M2M$RAMROM_DEV, R8
                MOVE    M2M$CONFIG, @R8
                MOVE    M2M$RAMROM_4KWIN, R8
                MOVE    M2M$CFG_GENERAL, @R8
                MOVE    M2M$CFG_VD_ITERSIZE, R8
                MOVE    @R8, R0                 ; R0: iteration size in bytes
                MOVE    VDRIVES_ITERSIZ, R1
                XOR     R7, R7
_START_VD_LP2   MOVE    R0, @R1++
                ADD     1, R7
                CMP     R6, R7
                RBRA    _START_VD_LP2, !Z

_VDI_RET        SYSCALL(leave, 1)
                RET

; ----------------------------------------------------------------------------
; Query & setter functions
; ----------------------------------------------------------------------------

; Check if the current mount status is different from the one we remembered
; Returns: Carry=1 if mount status is different (and in this case we remember
; automatically the new status), else Carry=0
; Additionally, returns the actual current mount status in R8
; Important: The mount status is for all drives, LSB=drive 0
VD_MNT_ST_GET   INCRB

                ; skip this function if there are no virtual drives at all
                RSUB    VD_ACTIVE, 1
                RBRA    _VDD_C0, !C

                ; retrieve current mount status
                MOVE    OPTM_MNT_STATUS, R0
                MOVE    VD_DRV_MOUNT, R8
                RSUB    VD_CAD_READ, 1

                ; did it change?
                CMP     @R0, R8
                RBRA    _VDD_C0, Z              ; no: leave with Carry=0

                ; yes: it did change: remember the new status and
                ; return with Carry=1
                MOVE    R8, @R0
                RBRA    _VDD_C1, 1

                ; DECRB and 
                ; RET done via _VDD_C0 and _VDD_C1 

; Remember the current mount status
VD_MNT_ST_SET   INCRB

                ; skip this function if there are no virtual drives at all
                RSUB    VD_ACTIVE, 1
                RBRA    _VD_MNT_ST_SR, !C

                MOVE    R8, R1

                MOVE    OPTM_MNT_STATUS, R0
                MOVE    VD_DRV_MOUNT, R8
                RSUB    VD_CAD_READ, 1
                MOVE    R8, @R0

                MOVE    R1, R8
_VD_MNT_ST_SR   DECRB
                RET

; Check if the write cache of any virtual drive is different from the one
; we remembered (and in this case we remember automatically the new status).
;
; Return Carry=1 if this is the case, else Carry=0. Also returns the actual
; status for each virtual drive as a bit-pattern in R8: LSB=drive 0, bit=0
; means write cache is clearn and bit=1 means write cache is dirty
VD_DTY_ST_GET   INCRB
                MOVE    R8, R0
                MOVE    R9, R1

                RSUB    VD_ACTIVE, 1            ; abort in case of no vdrives
                RBRA    _VDDTYGET_RET, !C

                ; get current status in @R5
                INCRB                           ; DECRB done in _VDDTY_GETINFO
                MOVE    R8, R2                  ; R2: amount of vdrives
                MOVE    SCRATCH_HEX, R5         ; R5: current status
                MOVE    0, @R5                  ; clear scratch buffer
                RSUB    _VDDTY_GETINFO, 1
                MOVE    SCRATCH_HEX, R5         ; due to DECRB in subroutine

                MOVE    OPTM_DTY_STATUS, R6
                CMP     @R5, @R6
                RBRA    _VDDTYGET_C0, Z         ; status did not change

                MOVE    @R5, @R6                ; remember new value (if any)
                MOVE    @R5, R8                 ; return status in R8
                MOVE    R1, R9                  ; restore R9
                RBRA    _VDD_C1, 1              ; return with Carry=1

_VDDTYGET_C0    MOVE    @R5, R8                 ; return status in R8
                MOVE    R1, R9                  ; restore R9
                RBRA    _VDD_C0, 1              ; return with Carry=0

_VDDTYGET_RET   MOVE    R0, R8
                MOVE    R1, R9
                RBRA    _VDD_C0, 1

                ; DECRB and 
                ; RET done via _VDD_C0 and _VDD_C1 

; Remember the write cache status of all virtual drives.
; See explanation of VD_DTY_ST_GET for details
VD_DTY_ST_SET   INCRB
                MOVE    R8, R0
                MOVE    R9, R1

                RSUB    VD_ACTIVE, 1            ; abort in case of no vdrives
                RBRA    _VDDTY_RET, !C
                MOVE    R8, R2                  ; R2: amount of vdrives
                MOVE    OPTM_DTY_STATUS, R5     ; R5: variable: remember stat.
                MOVE    0, @R5

                ; _VDDTY_GETINFO will be called from VD_DTY_ST_GET to
                ; retrieve the actual bitpattern and store it to where
                ; R5 points to
_VDDTY_GETINFO  XOR     R3, R3                  ; R3: current vdrive
                MOVE    1, R4                   ; R4: for set/clr bits

_VDDTY_1        MOVE    R3, R8                  ; read status for drv in R3
                MOVE    VD_CACHE_DIRTY, R9
                RSUB    VD_DRV_READ, 1
                CMP     1, R8                   ; cache dirty?
                RBRA    _VDDTY_2, !Z            ; no
                OR      R4, @R5                 ; set bit at current pos
                RBRA    _VDDTY_3, 1

_VDDTY_2        MOVE    R4, R6                  ; cache clean: clear bit
                NOT     R6, R6
                AND     R6, @R5

_VDDTY_3        AND     0xFFFD, SR              ; delete X as SHL fills with X
                SHL     1, R4                   ; next bit
                ADD     1, R3
                CMP     R2, R3                  ; all drives handled?
                RBRA    _VDDTY_1, !Z            ; no: continue with next vdrv

_VDDTY_RET      MOVE    R0, R8
                MOVE    R1, R9
                DECRB
                RET

; Check if the virtual drive system is active by checking, if there is at
; least one virtual drive.
;
; Returns: Carry=1 if active, else Carry=0
;          R8: Amount of vdrives
VD_ACTIVE       INCRB

                MOVE    VDRIVES_NUM, R8
                MOVE    @R8, R8
                RBRA    _VDA_C1, !Z
                AND     0xFFFB, SR              ; clear Carry
                RBRA    _VDA_RET, 1

_VDA_C1         OR      0x0004, SR              ; set Carry

_VDA_RET        DECRB
                RET

; Return the menu group ID of a single-select menu item that corresponds
; to the given virtual drive ID
;
; The first menu item in config.vhd with a OPTM_G_MOUNT_DRV flag is drive 0,
; the next one drive 1, etc.
;
; Input:        R8: virtual drive ID
; Output:       Carry=1 if any menu item is associated with virtual drive ID
;               R8: menu group ID, only valid if Carry=1
;               R9: menu item index starting from 0 for the first item
VD_MENGRP       INCRB

                XOR     R0, R0                  ; R0: current menu item index
                MOVE    -1, R1                  ; R1: vdrive counter
                MOVE    OPTM_ICOUNT, R2         ; R2: amount of menu items              
                MOVE    @R2, R2

                MOVE    M2M$RAMROM_DEV, R3      ; select configuration device
                MOVE    M2M$CONFIG, @R3
                MOVE    M2M$RAMROM_4KWIN, R3    ; select drv. mount items
                MOVE    M2M$CFG_OPTM_MOUNT, @R3
                MOVE    M2M$RAMROM_DATA, R3     ; R3: drive mount items

_VDMENGRP_1     CMP     1, @R3                  ; current item a drive?
                RBRA    _VDMENGRP_2, !Z         ; no
                ADD     1, R1                   ; yes: increase vdrive counter
                CMP     R8, R1                  ; found vdrive we look for?
                RBRA    _VDMENGRP_3, Z

_VDMENGRP_2     ADD     1, R3                   ; next item in vdrive array
                ADD     1, R0                   ; next menu item index
                CMP     R0, R2                  ; R0=R2 means one itm too much
                RBRA    _VDMENGRP_4, Z
                RBRA    _VDMENGRP_1, 1

                ; success
_VDMENGRP_3     MOVE    M2M$RAMROM_4KWIN, R4    ; select drv. mount items
                MOVE    M2M$CFG_OPTM_GROUPS, @R4
                MOVE    @R3, R8                 ; R8: group ID
                MOVE    R0, R9                  ; R9: index
                RBRA    _VDD_C1, 1

                ; failure
_VDMENGRP_4     MOVE    0xEEEE, R8
                MOVE    0xEEEE, R9
                RBRA    _VDD_C0, 1

                ; DECRB and 
                ; RET done via _VDD_C0 and _VDD_C1

; Return the drive number associated with a single-select menu item that
; as a unique menu group ID
;
; The first menu item in config.vhd with a OPTM_G_MOUNT_DRV flag is drive 0,
; the next one drive 1, etc.
;
; Input:   R8: menu item (menu group ID)
; Returns: Carry=1 if any drive number is associated with a menu item
;          R8: drive number, starting with 0, only valid if Carry=1
VD_DRVNO        INCRB

                ; step 1: find the menu item, i.e. get the index relative
                ; to the beginning of the data structure
                MOVE    OPTM_DATA, R0
                MOVE    @R0, R0
                ADD     OPTM_IR_GROUPS, R0
                MOVE    @R0, R0                 ; R0: start of data structure
                MOVE    OPTM_ICOUNT, R1
                MOVE    @R1, R1                 ; R1: amount of menu items
                XOR     R2, R2                  ; R2: index of drv. men. item

_VDD_1          CMP     R8, @R0++
                RBRA    _VDD_3, Z               ; menu item found
                ADD     1, R2
                SUB     1, R1
                RBRA    _VDD_1, !Z              ; check next item
_VDD_2          MOVE    0xFFFF, R8
                RBRA    _VDD_C0, 1              ; item not found

                ; step 2: check, if the menu item is a drive and find out the
                ; drive number by counting; R2 contains the index of the menu
                ; item that we are looking for
_VDD_3          XOR     R1, R1                  ; R1: drive number, if any
                XOR     R7, R7                  ; R7: index number
                MOVE    M2M$RAMROM_DEV, R0      ; select configuration device
                MOVE    M2M$CONFIG, @R0
                MOVE    M2M$RAMROM_4KWIN, R0    ; select drv. mount items
                MOVE    M2M$CFG_OPTM_MOUNT, @R0
                MOVE    M2M$RAMROM_DATA, R0     ; R0: ptr to data structure
_VDD_3A         CMP     R7, R2                  ; did we reach the item?
                RBRA    _VDD_5, !Z              ; no: continue to search
_VDD_4          CMP     1, @R0++                ; is the item a drive?
                RBRA    _VDD_2, !Z              ; no: return with C=0
                MOVE    R1, R8                  ; return drive number...
                RBRA    _VDD_C1, 1              ; ...with C=1
_VDD_5          CMP     1, @R0++                ; item at curr idx. drive?
                RBRA    _VDD_6, !Z              ; no
                ADD     1, R1                   ; count item as drive
_VDD_6          ADD     1, R7                   ; next index position
                RBRA    _VDD_3A, 1

                ; this code is re-used by other functions, do not change
_VDD_C0         AND     0xFFFB, SR              ; clear Carry
                RBRA    _VDD_RET, 1
_VDD_C1         OR      0x0004, SR              ; set Carry

_VDD_RET        DECRB
                RET

; Checks, if the given drive is mounted
;
; Input:   R8: drive number
; Returns: Carry=1 if drive is mounted
;          R8: drive number (unchanged)
VD_MOUNTED      INCRB

                MOVE    R8, R1
                MOVE    1, R0                   ; probe to check drive
                AND     0xFFFD, SR              ; clear X
                SHL     R8, R0                  ; drive 0 = LSB
                MOVE    VD_DRV_MOUNT, R8        ; get bitpattern of mounted..
                RSUB    VD_CAD_READ, 1          ; ..drives
                MOVE    R8, R2
                MOVE    R1, R8                  ; restore R8 (original drv. #)
                AND     R0, R2
                RBRA    _VDD_C1, !Z             ; yes: drive is mounted
                RBRA    _VDD_C0, 1              ; no: drive is not mounted

                ; DECRB and 
                ; RET done via _VDD_C0 and _VDD_C1

; Strobes the "image mount" signal: This is used to mount and to unmount
; drives: When the "image size" registers are non-zero, then the drive is
; mounted, otherwise it is held is reset state
;
; Input:   R8: drive number
;          R9/R10: low/high words of image size
;          R11: 1=read only
;          R12: disk image type
; Returns: R8 .. R12: unchanged
VD_STROBE_IM    INCRB

                ; save original register values
                MOVE    R8, R0                  ; R0: drive number
                MOVE    R9, R1                  ; R1: file size: low word
                MOVE    R10, R2                 ; R2: file size: high word
                MOVE    R11, R3                 ; R3: read-only flag
                MOVE    R12, R4                 ; R4: disk image type

                ; set file size, read-only and disk image type registers
                MOVE    VD_SIZE_L, R8
                MOVE    R1, R9
                RSUB    VD_CAD_WRITE, 1
                MOVE    VD_SIZE_H, R8
                MOVE    R2, R9
                RSUB    VD_CAD_WRITE, 1
                MOVE    VD_RO, R8
                MOVE    R3, R9
                RSUB    VD_CAD_WRITE, 1
                MOVE    VD_TYPE, R8
                MOVE    R4, R9
                RSUB    VD_CAD_WRITE, 1

                ; create bitmask for setting and deleting image mount bit
                MOVE    1, R6
                AND     0xFFFD, SR              ; clear X
                SHL     R0, R6                  ; R6: set flag, drive 0 = LSB
                NOT     R6, R7                  ; R7: used to clear flag

                ; get current bitmask and then strobe the flag
                MOVE    VD_IMG_MOUNT, R8
                RSUB    VD_CAD_READ, 1
                OR      R6, R8                  ; set flag
                MOVE    R8, R9
                MOVE    VD_IMG_MOUNT, R8
                RSUB    VD_CAD_WRITE, 1         ; set flag in register
                AND     R7, R9                  ; delete flag
                RSUB    VD_CAD_WRITE, 1         ; delete flag in register

                ; restore original register values
                MOVE    R0, R8              
                MOVE    R1, R9
                MOVE    R2, R10
                MOVE    R3, R11
                MOVE    R4, R12

                DECRB
                RET

; VDrives device: Read a value from the control and data registers
;
; Input:   R8: Register number
; Returns: R8: Value
VD_CAD_READ     INCRB

                MOVE    M2M$RAMROM_DEV, R0
                MOVE    VDRIVES_DEVICE, R1
                MOVE    @R1, @R0
                MOVE    M2M$RAMROM_4KWIN, R0
                MOVE    VD_WIN_CAD, @R0
                MOVE    @R8, R8

                DECRB
                RET

; VDrives device: Write a value to the control and data registers
;
; Input:   R8: Register number
;          R9: Value
; Returns: Nothing, leaves R8, R9 unchanged
VD_CAD_WRITE    INCRB

                MOVE    M2M$RAMROM_DEV, R0
                MOVE    VDRIVES_DEVICE, R1
                MOVE    @R1, @R0
                MOVE    M2M$RAMROM_4KWIN, R0
                MOVE    VD_WIN_CAD, @R0
                MOVE    R9, @R8

                DECRB
                RET

; VDrives device: Read a value from the virtual drive specific registers
; Input:   R8: Virtual drive number
;          R9: Register number
; Output:  R8: Value
; CAUTION: R8 is DESTROYED, i.e. the input value (the virtual drive number) is
;          overwritten by the return value. When iterating over all virtual
;          drives, keep the loop counter in another register and copy it to R8
;          before each call. (See VD_DRV_WRITE below, which in contrast to this
;          function does leave R8 unchanged.)
VD_DRV_READ     INCRB

                MOVE    M2M$RAMROM_DEV, R0
                MOVE    VDRIVES_DEVICE, R1
                MOVE    @R1, @R0
                MOVE    M2M$RAMROM_4KWIN, R0
                MOVE    VD_WIN_DRV, @R0
                ADD     R8, @R0                 ; drive windows are ascending
                MOVE    @R9, R8

                DECRB
                RET

; VDrives device: Write a value to the virtual drive specific registers
; Input:   R8:  Virtual drive number
;          R9:  Register number
;          R10: Value
; Output:  Nothing, leaves R8..R10 unchanged
VD_DRV_WRITE    INCRB

                MOVE    M2M$RAMROM_DEV, R0
                MOVE    VDRIVES_DEVICE, R1
                MOVE    @R1, @R0
                MOVE    M2M$RAMROM_4KWIN, R0
                MOVE    VD_WIN_DRV, @R0
                ADD     R8, @R0                 ; drive windows are ascending
                MOVE    R10, @R9

                DECRB
                RET

; ----------------------------------------------------------------------------
; Next disk
; ----------------------------------------------------------------------------

; Mount the disk image that follows the currently mounted disk image of a
; virtual drive in the same folder.
;
; Order and file filter are exactly the ones of the file browser: the list
; comes from DIRBROWSE_READ with FILTER_FILES in the context CTX_MOUNT_DISKIMG
; (the menu group id that FILTER_FILES gets in R11 is not set up: the C64
; core does not need it for disk images). Folders are skipped and after the
; last image the search wraps around to the first one. Images that
; PREP_LOAD_IMAGE rejects are skipped, too. If the mounted image is not part
; of the list of its folder, then the first image of the folder is mounted.
; The mount itself is done by HANDLE_MOUNTING with a preselected file
; (HM_PRESELECT), so the result equals a manual mount via the file browser,
; and the file browser afterwards continues in this folder with the cursor
; on the new image.
;
; Needs to run inside an options menu session (HANDLE_MOUNTING uses OPTM_SET)
; with OPTM_DIRECT set and the OSM hidden. While the image is loading, the
; full-screen window shows the progress bar; the OSM is hidden again when
; VD_NEXT_DISK returns. HANDLE_IO is not polled meanwhile.
;
; Input:
;   R8: Virtual drive number
; Output:
;   R8: 0 = OK: the next disk image is mounted
;       1 = No disk image is mounted on this drive
;       2 = There is no other (valid) disk image in the folder
;       3 = The write cache of the drive is dirty (saving is pending)
;       4 = SD card changed since the mount or folder is not readable
;       5 = Any other error (reserved: currently not returned)
;       In all cases but 0 the drive and its disk image did not change. The
;       file browser state may have changed (it is always consistent).
;   R9: If R8 = 0: File name of the new disk image (zero terminated); it
;       points into the file browser heap and is valid until the next
;       operation of the file browser or of VD_NEXT_DISK
;   R10..R12: Not preserved
VD_NEXT_DISK    INCRB

                MOVE    R8, R7                  ; R7: virtual drive number
                MOVE    1, R6                   ; R6: status: not mounted
                RSUB    VD_MOUNTED, 1
                RBRA    _VDNX_RET, !C

                ; The SD card must not have changed since the image was
                ; mounted: neither right now nor by a re-mount meanwhile
                MOVE    4, R6                   ; status: SD card changed
                MOVE    SD_CHANGED, R0
                MOVE    @R0, R0
                RBRA    _VDNX_RET, !Z
                MOVE    R7, R0                  ; R0: VD_NXT_INFO of drive
                ADD     R0, R0
                ADD     R0, R0
                ADD     VD_NXT_INFO, R0
                MOVE    @R0++, R1               ; 0: no folder remembered
                RBRA    _VDNX_RET, Z
                MOVE    VD_SDGEN, R2
                CMP     @R2, R1
                RBRA    _VDNX_RET, !Z
                MOVE    @R0++, R2               ; R2: folder: 1st cluster low
                MOVE    @R0++, R3               ; R3: folder: 1st cluster high
                                                ; R0: browser stack of folder

                ; Reuse the sorted list of the file browser if it belongs to
                ; this folder and to this drive (see _HM_SDMOUNTED2 for the
                ; FB_LASTCALLER encoding); otherwise read the folder
                MOVE    R7, R4
                SWAP    R4, R4                  ; R4: vdrive id + mode 0
                MOVE    HANDLE_DEV, R1
                ADD     FAT32$DEV_AD_1STCLUS_LO, R1
                CMP     @R1++, R2               ; R1: DEV_AD_1STCLUS_HI
                RBRA    _VDNX_READ, !Z
                CMP     @R1, R3
                RBRA    _VDNX_READ, !Z
                MOVE    FB_LASTCALLER, R8
                CMP     @R8, R4
                RBRA    _VDNX_READ, !Z
                MOVE    FB_HEAD, R5
                MOVE    @R5, R5                 ; R5: sorted directory list
                RBRA    _VDNX_FIND, !Z

_VDNX_READ      MOVE    R3, @R1                 ; change to the folder
                MOVE    R2, @--R1
                MOVE    SF_CONTEXT, R8          ; file filter context
                MOVE    CTX_MOUNT_DISKIMG, @R8
                MOVE    HANDLE_DEV, R8
                XOR     R9, R9                  ; read the active directory
                MOVE    FB_HEAP, R10
                MOVE    @R10, R10
                MOVE    HEAP_SIZE, R11
                MOVE    FILTER_FILES, R12
                RSUB    DIRBROWSE_READ, 1       ; R10: list, R11: status
                MOVE    R10, R5                 ; R5: sorted directory list

                ; The list replaced the one of the file browser: Make it the
                ; state of the file browser for this drive, as if the user had
                ; browsed to this folder: one cursor position (0) per folder
                ; level on the browser stack. Without a usable list, reset
                ; the file browser instead.
                RSUB    FB_RE_INIT, 1
                MOVE    4, R6                   ; status: folder not readable
                CMP     2, R11                  ; incomplete list: use it
                RBRA    _VDNX_INST, Z
                MOVE    R11, R11
                RBRA    _VDNX_RET, !Z
_VDNX_INST      MOVE    2, R6                   ; status: no other image
                MOVE    R5, R5                  ; empty folder?
                RBRA    _VDNX_RET, Z
                MOVE    FB_HEAD, R8
                MOVE    R5, @R8
                MOVE    FB_LASTCALLER, R8
                MOVE    R4, @R8
                MOVE    @R0, R1                 ; R1: browser stack of folder
                MOVE    FB_STACK, R8
                MOVE    R1, @R8
                MOVE    FB_STACK_INIT, R8
                MOVE    @R8, R8
                ADD     2, R8                   ; R8: bottom of browser stack
_VDNX_STACK     CMP     R8, R1
                RBRA    _VDNX_FIND, Z
                MOVE    0, @R1++
                RBRA    _VDNX_STACK, 1

                ; Next image after the mounted one (by its start cluster)
_VDNX_FIND      MOVE    HNDL_VD_FILES, R10
                ADD     R7, R10
                MOVE    @R10, R10
                ADD     FAT32$FDH_START_CLUS_LO, R10
                MOVE    @R10++, R9              ; FDH_START_CLUS_HI follows
                MOVE    @R10, R10
                MOVE    R5, R8
                RSUB    DIRBROWSE_NEXT, 1       ; R10: candidate, R11: index
                MOVE    R9, R4                  ; R4: end of circle or 0
_VDNX_CHK       MOVE    2, R6                   ; status: no other image
                MOVE    R10, R10                ; no image at all?
                RBRA    _VDNX_RET, Z
                CMP     R10, R4                 ; circle complete?
                RBRA    _VDNX_RET, Z
                MOVE    R4, R4                  ; mounted image not in list:
                RBRA    _VDNX_TRY, !Z           ; the first candidate marks..
                MOVE    R10, R4                 ; ..the end of the circle
_VDNX_TRY       MOVE    R10, R2                 ; R2: candidate
                MOVE    R11, R3                 ; R3: index of candidate
                MOVE    R10, R1
                ADD     SLL$DATA, R1            ; R1: file name

                ; Check the candidate with PREP_LOAD_IMAGE before mounting it:
                ; LOAD_IMAGE reopens the file handle of the drive, so if it
                ; rejected the image, then the drive would keep the old image
                ; while its handle would point to the new file.
                MOVE    HANDLE_DEV, R8
                MOVE    _DIRBR_FH, R9           ; scratch file handle
                MOVE    R1, R10
                XOR     R11, R11
                SYSCALL(f32_fopen, 1)
                MOVE    R10, R10
                RBRA    _VDNX_SKIP, !Z
                MOVE    R9, R8                  ; R8: file handle
                MOVE    CTX_MOUNT_DISKIMG, R9   ; R9: context, R10: 0
                RSUB    PREP_LOAD_IMAGE, 1
                MOVE    R8, R8
                RBRA    _VDNX_LOAD, Z
_VDNX_SKIP      MOVE    R2, R10                 ; continue after the candidate:
                ADD     SLL$DATA_SIZE, R10      ; its start cluster is at the..
                ADD     @R10, R10               ; ..end of its data blob
                MOVE    @R10, R11
                MOVE    @--R10, R9
                MOVE    R11, R10
                MOVE    R5, R8
                RSUB    DIRBROWSE_NEXT, 1
                RBRA    _VDNX_CHK, 1

                ; Mount the candidate the regular way, but without browser
_VDNX_LOAD      MOVE    HM_PRESELECT, R0
                MOVE    R1, @R0
                MOVE    R7, R8                  ; R8: virtual drive number
                XOR     R9, R9                  ; R9: not OPTM_KEY_SELALT
                XOR     R10, R10                ; R10: virtual drive mode
                RSUB    HANDLE_MOUNTING, 1
                MOVE    @R0, R8                 ; not consumed: the write..
                XOR     @R0, @R0                ; ..cache is dirty
                MOVE    3, R6                   ; status: write cache dirty
                MOVE    R8, R8
                RBRA    _VDNX_RET, !Z
                MOVE    FB_STACK, R8            ; cursor of the file browser..
                MOVE    @R8, R8                 ; ..on the new image
                MOVE    R3, @R8
                XOR     R6, R6                  ; status: OK

_VDNX_RET       MOVE    R6, R8
                MOVE    R1, R9
                DECRB
                RET
