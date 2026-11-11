; ****************************************************************************
; MiSTer2MEGA65 (M2M) QNICE ROM
;
; Testbed for the selection logic of the Next disk feature (VD_NEXT_DISK in
; ../vdrives.asm): the cluster-aware directory list of DIRBROWSE_READ and the
; ring walk of DIRBROWSE_NEXT in ../dirbrowse.asm.
;
; Driven by next_disk_test.py, which builds an MBR plus FAT32 image with long
; file names, runs this program in the QNICE emulator (the image is attached
; as the SD card) and compares the output with an independent Python model
; of the file browser (filter, sort order, directories first).
;
; For each test case (folder, mounted file) the testbed does what the Shell
; does: It opens the mounted file to obtain its start cluster (like
; LOAD_IMAGE), changes to the folder and remembers its first cluster (like
; HANDLE_MOUNTING), moves away to the root and then returns to the folder by
; setting the active directory cluster directly (like VD_NEXT_DISK). Then it
; reads the folder with DIRBROWSE_READ (R9 = 0: active directory) and prints
;
;   E <flag> <cluster hi> <cluster lo> <name>   for each list element
;   CUR <name> or CUR -                         the mounted file in the list
;   NEXT <name>@<index> or NEXT -               the next image
;   RING <name>@<index>|...                     the whole ring from NEXT on
;
; done by sy2002 in November 2026 and licensed under GPL v3
; ****************************************************************************

#include "../../QNICE/dist_kit/sysdef.asm"
#include "../../QNICE/dist_kit/monitor.def"

CTX_MOUNT_DISKIMG .EQU 0x0100                   ; see ../sysdef.asm
RING_MAX        .EQU 100                        ; guard against endless rings

                .ORG    0x8000

                MOVE    STR_TITLE, R8
                SYSCALL(puts, 1)

                MOVE    HANDLE_DEV, R8          ; mount partition 1
                MOVE    1, R9
                SYSCALL(f32_mnt_sd, 1)
                CMP     0, R9
                RBRA    MOUNT_OK, Z
                MOVE    STR_E_MNT, R8
                RBRA    DIE, 1

MOUNT_OK        MOVE    SF_CONTEXT, R8          ; context of the file filter
                MOVE    CTX_MOUNT_DISKIMG, @R8
                MOVE    SF_CONTEXT_DATA, R8
                MOVE    0, @R8

                MOVE    CASES, R0               ; R0: (folder, file) pairs

CASE_LOOP       MOVE    @R0++, R1               ; R1: folder
                RBRA    ALL_DONE, Z
                MOVE    @R0++, R2               ; R2: mounted file (path)

                MOVE    STR_CASE, R8
                SYSCALL(puts, 1)
                MOVE    R1, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)

                ; 1. open the mounted file: its start cluster identifies it
                MOVE    HANDLE_DEV, R8
                MOVE    FILE_HANDLE, R9
                MOVE    R2, R10
                XOR     R11, R11
                SYSCALL(f32_fopen, 1)
                CMP     0, R10
                RBRA    FOPEN_OK, Z
                MOVE    STR_E_FOPEN, R8
                RBRA    DIE, 1

                ; 2. change to the folder and remember its first cluster
FOPEN_OK        MOVE    HANDLE_DEV, R8
                MOVE    R1, R9
                XOR     R10, R10
                SYSCALL(f32_cd, 1)
                CMP     0, R9
                RBRA    CD_OK, Z
                MOVE    STR_E_CD, R8
                RBRA    DIE, 1
CD_OK           MOVE    HANDLE_DEV, R3
                ADD     FAT32$DEV_AD_1STCLUS_LO, R3
                MOVE    @R3++, R4               ; R4: folder cluster low
                MOVE    @R3, R5                 ; R5: folder cluster high

                ; 3. move away and come back by setting the cluster directly
                MOVE    HANDLE_DEV, R8
                MOVE    STR_ROOT, R9
                XOR     R10, R10
                SYSCALL(f32_cd, 1)
                MOVE    R5, @R3
                MOVE    R4, @--R3

                ; 4. read the active directory: sorted and filtered list
                MOVE    HANDLE_DEV, R8
                XOR     R9, R9
                MOVE    HEAP, R10
                MOVE    HEAP_SIZE, R11
                MOVE    FILTER_FILES, R12
                RSUB    DIRBROWSE_READ, 1
                CMP     0, R11
                RBRA    READ_OK, Z
                MOVE    STR_E_READ, R8
                RBRA    DIE, 1
READ_OK         MOVE    R10, R6                 ; R6: head of the list

                ; print all list elements: flag and cluster from the end of
                ; the data blob (same layout that _ELEMENT_FOUND relies on)
                MOVE    R6, R7
PRINT_ELM       CMP     0, R7
                RBRA    PRINT_ELM_END, Z
                MOVE    STR_E, R8
                SYSCALL(puts, 1)
                MOVE    R7, R3
                ADD     SLL$DATA_SIZE, R3
                MOVE    @R3, R3
                ADD     R7, R3                  ; R3: directory flag
                MOVE    @R3++, R8
                SYSCALL(puthex, 1)
                RSUB    PRINT_SPACE, 1
                MOVE    @R3++, R4               ; R4: cluster low
                MOVE    @R3, R8                 ; cluster high
                SYSCALL(puthex, 1)
                RSUB    PRINT_SPACE, 1
                MOVE    R4, R8
                SYSCALL(puthex, 1)
                RSUB    PRINT_SPACE, 1
                MOVE    R7, R8
                ADD     SLL$DATA, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                MOVE    @R7, R7
                RBRA    PRINT_ELM, 1

                ; 5. next image after the mounted file
PRINT_ELM_END   MOVE    FILE_HANDLE, R10
                ADD     FAT32$FDH_START_CLUS_LO, R10
                MOVE    @R10++, R9              ; R9: start cluster low
                MOVE    @R10, R10               ; R10: start cluster high
                MOVE    R6, R8
                RSUB    DIRBROWSE_NEXT, 1
                MOVE    R10, R4                 ; R4: start of the ring

                MOVE    STR_CUR, R8
                SYSCALL(puts, 1)
                MOVE    R9, R8
                RSUB    PRINT_ELMNAME, 1
                SYSCALL(crlf, 1)

                MOVE    STR_NEXT, R8
                SYSCALL(puts, 1)
                MOVE    R10, R8
                MOVE    R11, R9
                RSUB    PRINT_ELMIDX, 1
                SYSCALL(crlf, 1)

                ; 6. walk the ring of images, continuing after each one by
                ; its start cluster (like the skip loop of VD_NEXT_DISK)
                MOVE    STR_RING, R8
                SYSCALL(puts, 1)
                CMP     0, R4
                RBRA    RING_END, Z
                MOVE    RING_MAX, R5
RING_LOOP       MOVE    R10, R8
                MOVE    R11, R9
                RSUB    PRINT_ELMIDX, 1
                MOVE    R10, R7                 ; cluster of this image
                ADD     SLL$DATA_SIZE, R7
                ADD     @R7, R7
                MOVE    @R7, R10                ; high
                MOVE    @--R7, R9               ; low
                MOVE    R6, R8
                RSUB    DIRBROWSE_NEXT, 1
                CMP     R10, R4
                RBRA    RING_END, Z
                MOVE    STR_BAR, R8
                SYSCALL(puts, 1)
                SUB     1, R5
                RBRA    RING_LOOP, !Z
                MOVE    STR_E_RING, R8
                RBRA    DIE, 1
RING_END        SYSCALL(crlf, 1)
                RBRA    CASE_LOOP, 1

ALL_DONE        MOVE    STR_DONE, R8
                SYSCALL(puts, 1)
                SYSCALL(exit, 1)

DIE             SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                SYSCALL(exit, 1)

; print the name of list element R8 or "-" if R8 is 0
PRINT_ELMNAME   INCRB
                MOVE    R8, R0
                MOVE    STR_NONE, R8
                CMP     0, R0
                RBRA    _PEN_PRINT, Z
                MOVE    R0, R8
                ADD     SLL$DATA, R8
_PEN_PRINT      SYSCALL(puts, 1)
                MOVE    R0, R8
                DECRB
                RET

; print the name of list element R8 followed by @ and its index in R9
PRINT_ELMIDX    INCRB
                RSUB    PRINT_ELMNAME, 1
                CMP     0, R8
                RBRA    _PEI_RET, Z
                MOVE    R8, R0
                MOVE    STR_AT, R8
                SYSCALL(puts, 1)
                MOVE    R9, R8
                SYSCALL(puthex, 1)
                MOVE    R0, R8
_PEI_RET        DECRB
                RET

PRINT_SPACE     INCRB
                MOVE    R8, R0
                MOVE    STR_SPACE, R8
                SYSCALL(puts, 1)
                MOVE    R0, R8
                DECRB
                RET

; File filter with the semantics of FILTER_FILES in CORE/m2m-rom/m2m-rom.asm
; for the context CTX_MOUNT_DISKIMG: directories are shown, files only if
; they end with .D64 or .D81 (R8 is the upper case name, R9 = 1: directory).
; Returns R8 = 0 to show the entry and R8 = 1 to filter it.
FILTER_FILES    INCRB
                MOVE    R9, R0
                XOR     R1, R1                  ; R1: 0 = show
                CMP     1, R9
                RBRA    _FF_RET, Z
                MOVE    1, R1                   ; filter by default
                SYSCALL(strlen, 1)
                CMP     4, R9                   ; shorter than 4 chars?
                RBRA    _FF_RET, N
                ADD     R8, R9
                SUB     4, R9                   ; R9: last 4 chars
                MOVE    EXT_D64, R8
                SYSCALL(strcmp, 1)
                CMP     0, R10
                RBRA    _FF_SHOW, Z
                MOVE    EXT_D81, R8
                SYSCALL(strcmp, 1)
                CMP     0, R10
                RBRA    _FF_RET, !Z
_FF_SHOW        XOR     R1, R1
_FF_RET         MOVE    R1, R8
                MOVE    R0, R9
                DECRB
                RET

; ----------------------------------------------------------------------------
; Test cases: pairs of (folder, mounted file), terminated by 0
; ----------------------------------------------------------------------------

CASES           .DW     F_DISKS, M_ZORK         ; wrap-around from the last
                .DW     F_DISKS, M_GAME1        ; names that differ late
                .DW     F_DISKS, M_ELSEWHERE    ; mounted file not in folder
                .DW     F_NUMS, M_N10           ; number-like names
                .DW     F_SINGLE, M_ONLY        ; single image
                .DW     F_EMPTY, M_ELSEWHERE    ; no image at all
                .DW     F_LONG, M_LONGA         ; long names, multi-cluster
                .DW     F_ROOT, M_ROOT1         ; root folder, 8.3 names
                .DW     0

F_DISKS         .ASCII_W "/DISKS"
F_NUMS          .ASCII_W "/NUMS"
F_SINGLE        .ASCII_W "/SINGLE"
F_EMPTY         .ASCII_W "/EMPTY"
F_LONG          .ASCII_W "/LONG"
F_ROOT          .ASCII_W "/"
M_ZORK          .ASCII_W "/DISKS/Zork.d64"
M_GAME1         .ASCII_W "/DISKS/Game Disk 1.d64"
M_ELSEWHERE     .ASCII_W "/OTHER/elsewhere.d64"
M_N10           .ASCII_W "/NUMS/10.d64"
M_ONLY          .ASCII_W "/SINGLE/only.d64"
M_LONGA         .ASCII_P "/LONG/The Very Long Adventure Game With A Name "
                .ASCII_P "That Goes On And On Beyond Everything A File "
                .ASCII_W "Browser Can Show On One Line - Side A.d64"
M_ROOT1         .ASCII_W "/ROOT1.D64"

STR_TITLE       .ASCII_W "next_disk_test: DIRBROWSE_READ + DIRBROWSE_NEXT\n"
STR_CASE        .ASCII_W "CASE "
STR_E           .ASCII_W "E "
STR_CUR         .ASCII_W "CUR "
STR_NEXT        .ASCII_W "NEXT "
STR_RING        .ASCII_W "RING "
STR_NONE        .ASCII_W "-"
STR_AT          .ASCII_W "@"
STR_BAR         .ASCII_W "|"
STR_SPACE       .ASCII_W " "
STR_ROOT        .ASCII_W "/"
STR_DONE        .ASCII_W "TESTBED-DONE\n"
STR_E_MNT       .ASCII_W "ERROR: cannot mount the SD card image"
STR_E_FOPEN     .ASCII_W "ERROR: cannot open the mounted file"
STR_E_CD        .ASCII_W "ERROR: cannot change to the folder"
STR_E_READ      .ASCII_W "ERROR: DIRBROWSE_READ failed"
STR_E_RING      .ASCII_W "ERROR: the ring does not close"
EXT_D64         .ASCII_W ".D64"
EXT_D81         .ASCII_W ".D81"

; ----------------------------------------------------------------------------
; Variables
; ----------------------------------------------------------------------------

HANDLE_DEV      .BLOCK  FAT32$DEV_STRUCT_SIZE
FILE_HANDLE     .BLOCK  FAT32$FDH_STRUCT_SIZE

#include "../dirbrowse_vars.asm"

; minimal stand-ins for the SELECT_FILE context variables of shell_vars.asm
SF_CONTEXT      .BLOCK 1
SF_CONTEXT_DATA .BLOCK 1

#include "../dirbrowse.asm"

HEAP_SIZE       .EQU 8192
HEAP            .BLOCK 1
