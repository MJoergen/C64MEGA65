; ****************************************************************************
; MiSTer2MEGA65 (M2M) QNICE ROM
;
; Directory Browser (with sorted output)
;
; Change in 2023: While this was originally made to be reusable also outside
; of the context of the Shell, from now on dirbrowse.asm is dependent on the
; global variable SF_CONTEXT in shell_vars.asm which will be handed over as a
; parameter R10 to the filter function in _DIRBR_FILTENT. To undo this
; change, delete this comment and everything tagged with SF_CONTEXT in
; _DIRBR_FILTENT.
;
; done by sy2002 in 2022, 2023 and licensed under GPL v3
; ****************************************************************************

#include "llist.asm"

_DIRBR_DOT      .ASCII_W "."                    ; filter this from dir. views
_DIRBR_DS       .EQU    0x3C                    ; ASCII of "<"
_DIRBR_DE       .EQU    0x3E                    ; ASCII of ">"
_DIRBR_DSDESIZE .EQU    2                       ; amount of characters in sum

; Data of a list element (behind the three header words, see SLL$DATA in
; llist.asm):
;   DIRBR$FLAGS: DIRBR$FLAG_DIR for a directory, DIRBR$FLAG_NUM if the name
;                consists of digits only (for the sort order)
;   DIRBR$CLUS_LO, DIRBR$CLUS_HI: start cluster of the file or directory
;                (see DIRBROWSE_NEXT)
;   DIRBR$NAME:  the name with two characters per word, the first one in
;                the high byte, ending with a zero byte: a name with an even
;                amount of characters ends with the word 0x0000. Directory
;                names are enclosed in "<" and ">".
; DIRBR$GETNAME and DIRBR$UNPACK return the name as a normal string.
DIRBR$FLAGS     .EQU    0                       ; offset from SLL$DATA
DIRBR$CLUS_LO   .EQU    1                       ; offset from SLL$DATA
DIRBR$CLUS_HI   .EQU    2                       ; offset from SLL$DATA
DIRBR$NAME      .EQU    3                       ; offset from SLL$DATA
DIRBR$FLAG_DIR  .EQU    0x0001
DIRBR$FLAG_NUM  .EQU    0x0002

; DIRBROWSE_READ keeps a buffer for DIRBR$GETNAME at the end of its heap:
; "<" + up to 256 characters + ">" + zero terminator
DIRBR$NAMEBUF_SIZE .EQU 259

; ----------------------------------------------------------------------------
; Read and sort all contents of the given path into a heap memory structure
; Input:
;   R8: Pointer to valid device handle
;   R9: Pointer to path that shall be listed (zero-terminated string) or
;       0 to list the currently active directory of the device handle
;  R10: Pointer to heap
;  R11: Maximum amount of available heap memory; the last DIRBR$NAMEBUF_SIZE
;       words of it are the name buffer of DIRBR$GETNAME
;  R12: Optional filter function that filters out files of a certain name.
;       The filter function takes a pointer to a string in R8 and a directory
;       flag in R9 (0=it is a file, 1=it is a directory) and returns 0 in R8,
;       if the file shall not be filtered and 1 if it shall be filtered.
;       The string provided in R8 is always in upper case.
;       If R12 is zero, then no filter is applied.
;       Filtered entries take no heap space.
; Output:
;   R8: (unchanged) Pointer to valid device handle
;   R9: Amount of directory entries in the list
;  R10: head of sorted linked list
;  R11: Return code:
;       0 = OK
;       1 = directory not found
;       2 = more directory items available than memory permits
;       <other value> = error code
; ----------------------------------------------------------------------------

DIRBROWSE_READ  INCRB
                MOVE    R8, R0
                MOVE    R12, R1
                INCRB

                MOVE    R10, R0                 ; R0: head of the heap
                MOVE    R10, R1                 ; R1: current heap ptr
                MOVE    R11, R2                 ; R2: max memory on heap..
                SUB     DIRBR$NAMEBUF_SIZE, R2  ; ..minus the name buffer
                MOVE    R10, R7                 ; the name buffer sits at..
                ADD     R2, R7                  ; ..the end of the heap
                MOVE    _DIRBR_NAMEBUF, R6
                MOVE    R7, @R6
                XOR     R3, R3                  ; R3: current heap mem. usage
                XOR     R4, R4                  ; R4: amount of entries read
                XOR     R5, R5                  ; R5: head of linked list
                MOVE    _DIRBR_FILTERFN, R6     ; remember the filter function
                MOVE    R12, @R6                ; for _DIRBR_FILTENT
                MOVE    R12, R6                 ; R6: filter function or 0
                                                ; R7: directory handle

                ; change directory to given path (if any) and then obtain the
                ; directory handle: R8: device handle, R9: path
_DIRBR_START    XOR     R10, R10                ; use "/" as separator char
                MOVE    R9, R9                  ; no path given?
                RBRA    _DIRBR_OPEN, Z          ; yes: stay where we are
                SYSCALL(f32_cd, 1)              ; change directory
                CMP     0, R9                   ; everything OK?
                RBRA    _DIRBR_RD_ECD, !Z       ; no: error and exit
                                                ; R8: still contains dev. hndl
_DIRBR_OPEN     MOVE    _DIRBR_FH, R9           ; R9: empty directory handle
                SYSCALL(f32_od, 1)              ; obtain directory handle
                MOVE    R8, R7                  ; R7: directory handle
                CMP     0, R9                   ; everything OK?
                RBRA    _DIRBR_RD_EDH, !Z       ; no: exit with error code

                ; iterate through the current directory
_DIRBR_LOOP     MOVE    R7, R8                  ; R8: directory handle
                MOVE    _DIRBR_ENTRY, R9        ; R9: empty dir. entry struct
                MOVE    FAT32$FA_DEFAULT, R10   ; R10: browse for all
                                                ; non-hidden files and dirs
                SYSCALL(f32_ld, 1)              ; get next directory entry
                CMP     0, R11                  ; any errors?
                RBRA    _DIRBR_RD_RET, !Z       ; yes: exit with error in R11
                CMP     1, R10                  ; current entry valid?
                RBRA    _DIRBR_LOOPEND, !Z      ; no: end loop

                MOVE    _DIRBR_DOT, R8          ; filter the "single dot"
                MOVE    _DIRBR_ENTRY, R9
                ADD     FAT32$DE_NAME, R9
                SYSCALL(strcmp, 1)
                CMP     0, R10
                RBRA    _DIRBR_LOOP, Z

                ; apply the filter before the entry takes any heap space,
                ; so that hidden files do not count against the heap
                CMP     0, R6                   ; filter function given?
                RBRA    _DIRBR_NEW, Z           ; no: keep every entry
                RSUB    _DIRBR_FILTENT, 1       ; R8 = 1: hide this entry
                CMP     1, R8
                RBRA    _DIRBR_LOOP, Z          ; hidden: next entry

_DIRBR_NEW      MOVE    R1, R8                  ; R1: current heap ptr
                MOVE    R2, R9                  ; R2: maximum heap memory
                MOVE    R3, R10                 ; R3: current heap memory
                RSUB    _DIRBR_NEWELM, 1        ; new element on heap
                MOVE    R8, R1                  ; R1: new heap ptr
                MOVE    R10, R3                 ; R3: new current heap memory
                CMP     0, R11                  ; out-of-memory?
                RBRA    _DIRBR_RD_WOOM, !Z      ; yes: exit

                ADD     1, R4                   ; one more entry read

                MOVE    R5, R8                  ; R8: head of linked list
                                                ; R9: still has new element
                XOR     R10, R10                ; R10: no filter (done above)
                                                ; (R11 unused by SLL$APPEND)

                RSUB    SLL$APPEND, 1           ; O(1) tail append; the
                                                ; sort is done once after
                                                ; the build loop (see #228)
                MOVE    R8, R5                  ; R5: (new) head of linked lst
                RBRA    _DIRBR_LOOP, 1          ; next iteration

_DIRBR_LOOPEND  ; sort the assembled list before returning it
                MOVE    R5, R8
                MOVE    _DIRBR_COMPARE, R9
                RSUB    SLL$SORT, 1
                MOVE    R8, R5                  ; R5: new sorted head

                MOVE    R4, R9                  ; return amount of entries
                MOVE    R5, R10                 ; R10: head of linked list
                XOR     R11, R11                ; 0 = no error
                RBRA    _DIRBR_RD_RET, 1

_DIRBR_RD_ECD   MOVE    1, R11                  ; directory not found
                RBRA    _DIRBR_RD_RET, 1
_DIRBR_RD_WOOM  ; sort the partial list so the caller still sees it sorted
                MOVE    R5, R8
                MOVE    _DIRBR_COMPARE, R9
                RSUB    SLL$SORT, 1
                MOVE    R8, R5                  ; R5: new sorted head

                MOVE    2, R11                  ; out-of-memory
                MOVE    R4, R9                  ; amount of entries
                MOVE    R5, R10                 ; head of linked list
                RBRA    _DIRBR_RD_RET, 1
_DIRBR_RD_EDH   MOVE    R9, R11                 ; return R9 as error code
_DIRBR_RD_RET   DECRB
                MOVE    R0, R8
                MOVE    R1, R12
                DECRB
                RET

; ----------------------------------------------------------------------------
; Find the file that follows a given file in a list from DIRBROWSE_READ
;
; Directories are skipped and after the last file the search wraps around to
; the first file of the list, so the files form a ring in exactly the order
; in which the file browser shows them. The given file is identified by its
; start cluster (an open file handle knows it as FAT32$FDH_START_CLUS_*),
; which is robust and needs no copy of its long name. If the given file is
; not part of the list (for example because it was beyond the memory limit
; of the list), then the first file of the list is returned.
;
; Input:
;   R8: Head of the linked list (as returned by DIRBROWSE_READ), may be 0
;   R9: Start cluster of the given file: low word
;  R10: Start cluster of the given file: high word
; Output:
;   R8: (unchanged)
;   R9: List element of the given file or 0 if it is not part of the list
;  R10: List element of the next file or 0 if there are no files in the
;       list; if the given file is the only one, then R10 equals R9
;  R11: Absolute index of R10 within the list (head = 0); this is the cursor
;       position of the file browser that selects R10
; ----------------------------------------------------------------------------

DIRBROWSE_NEXT  INCRB

                MOVE    R8, R0                  ; R0: current element
                XOR     R1, R1                  ; R1: index of R0
                XOR     R2, R2                  ; R2: first file of the list
                XOR     R3, R3                  ; R3: index of R2
                XOR     R4, R4                  ; R4: element of given file

_DIRBR_NX_LOOP  MOVE    R0, R0                  ; end of list reached?
                RBRA    _DIRBR_NX_WRAP, Z       ; yes: wrap around

                ; the data blob starts with the flags and the start cluster
                ; (see DIRBR$FLAGS)
                MOVE    R0, R5
                ADD     SLL$DATA, R5            ; R5: data blob
                MOVE    R5, R6
                ADD     DIRBR$CLUS_HI, R6
                MOVE    @R6, R6                 ; R6: start cluster high
                MOVE    R5, R7
                ADD     DIRBR$CLUS_LO, R7
                MOVE    @R7, R7                 ; R7: start cluster low
                ADD     DIRBR$FLAGS, R5
                MOVE    @R5, R5
                AND     DIRBR$FLAG_DIR, R5      ; directory?
                RBRA    _DIRBR_NX_NEXT, !Z      ; skip directories
                MOVE    R6, R5                  ; skip empty files: they all
                OR      R7, R5                  ; have start cluster 0, which
                RBRA    _DIRBR_NX_NEXT, Z       ; is ambiguous (endless walk)

                MOVE    R2, R2                  ; first file of the list?
                RBRA    _DIRBR_NX_CHK, !Z       ; no
                MOVE    R0, R2                  ; yes: remember it
                MOVE    R1, R3
_DIRBR_NX_CHK   MOVE    R4, R4                  ; given file passed?
                RBRA    _DIRBR_NX_FOUND, !Z     ; yes: this is the next file
                CMP     R6, R10                 ; is this the given file?
                RBRA    _DIRBR_NX_NEXT, !Z
                CMP     R7, R9
                RBRA    _DIRBR_NX_NEXT, !Z
                MOVE    R0, R4                  ; yes: the next file wins

_DIRBR_NX_NEXT  MOVE    @R0, R0                 ; SLL$NEXT is at offset 0
                ADD     1, R1
                RBRA    _DIRBR_NX_LOOP, 1

_DIRBR_NX_WRAP  MOVE    R2, R0                  ; first file of the list..
                MOVE    R3, R1                  ; ..or 0 if there is none
_DIRBR_NX_FOUND MOVE    R4, R9
                MOVE    R0, R10
                MOVE    R1, R11
                DECRB
                RET

; ----------------------------------------------------------------------------
; Name of a list element of DIRBROWSE_READ as a normal string with one
; character per word (directory names keep their "<" and ">"). The name is
; copied to the name buffer at the end of the heap of DIRBROWSE_READ, so it
; stays valid until the next call of DIRBR$GETNAME or DIRBROWSE_READ.
; Input:
;   R8: list element
; Output:
;   R8: name (zero-terminated)
;   R9: flags of the element (DIRBR$FLAG_DIR, DIRBR$FLAG_NUM)
; ----------------------------------------------------------------------------

DIRBR$GETNAME   INCRB
                MOVE    R10, R0
                MOVE    R8, R1
                MOVE    _DIRBR_NAMEBUF, R9
                MOVE    @R9, R9                 ; R9: name buffer
                MOVE    DIRBR$NAMEBUF_SIZE, R10
                SUB     1, R10                  ; R10: maximum length
                RSUB    DIRBR$UNPACK, 1
                MOVE    R9, R8                  ; R8: name
                ADD     SLL$DATA, R1
                ADD     DIRBR$FLAGS, R1
                MOVE    @R1, R9                 ; R9: flags
                MOVE    R0, R10
                DECRB
                RET

; ----------------------------------------------------------------------------
; Copy the name of a list element of DIRBROWSE_READ into a buffer as a normal
; string with one character per word (directory names keep their "<" and
; ">"). At most R10 characters are copied.
; Input:
;   R8: list element
;   R9: buffer of at least R10 + 1 words
;  R10: maximum amount of characters to copy (0 .. 0x7FFF)
; Output:
;   R8, R9: unchanged, the string in the buffer is zero-terminated
;  R10: length of the whole name: larger than the input R10 if the name did
;       not fit
; ----------------------------------------------------------------------------

DIRBR$UNPACK    INCRB
                MOVE    R8, R0
                ADD     SLL$DATA, R0
                ADD     DIRBR$NAME, R0          ; R0: packed name
                MOVE    R9, R1                  ; R1: target
                MOVE    R10, R2                 ; R2: room left
                XOR     R3, R3                  ; R3: length of the name
_DIRBR_UP_LOOP  MOVE    @R0++, R4               ; R4: two characters
                SWAP    R4, R5
                AND     0x00FF, R5              ; R5: first character
                RBRA    _DIRBR_UP_END, Z
                ADD     1, R3
                SUB     1, R2                   ; room for it?
                RBRA    _DIRBR_UP_2ND, N        ; no
                MOVE    R5, @R1++
_DIRBR_UP_2ND   AND     0x00FF, R4              ; R4: second character
                RBRA    _DIRBR_UP_END, Z
                ADD     1, R3
                SUB     1, R2                   ; room for it?
                RBRA    _DIRBR_UP_LOOP, N       ; no
                MOVE    R4, @R1++
                RBRA    _DIRBR_UP_LOOP, 1
_DIRBR_UP_END   MOVE    0, @R1                  ; zero terminator
                MOVE    R3, R10
                DECRB
                RET

; ----------------------------------------------------------------------------
; Internal helper functions
; ----------------------------------------------------------------------------

; Create new linked-list element on the heap, manage the heap-head and return
; a pointer to the new element in R8
; Input:
;   R8: Pointer to the head of the heap
;   assumes a valid directoy entry structure in _DIRBR_ENTRY
;   R9: maximum heap memory
;  R10: current heap memory
; Output;
;   R8: Adjusted pointer to the head of the heap
;   R9: Pointer to new linked-list element on the heap
;  R10: new current heap memory
;  R11: 0: OK, 1: out-of-memory
_DIRBR_NEWELM   INCRB

                MOVE    R8, R11                 ; R11: new linked-list elm.
                MOVE    R8, R0                  ; R0: NEXT
                MOVE    R8, R1                  ; R1: PREV
                MOVE    R8, R2                  ; R2: DATA-SIZE
                MOVE    R8, R3                  ; R3: DATA
                MOVE    R9, R4                  ; R4: maximum heap memory
                MOVE    R10, R5                 ; R5: current heap memory
                XOR     R6, R6                  ; R6: is it a directory?
                ADD     SLL$NEXT, R0
                ADD     SLL$PREV, R1
                ADD     SLL$DATA_SIZE, R2
                ADD     SLL$DATA, R3

                ; determine the length of the file/directory name and
                ; calculate the size of the data blob (see DIRBR$FLAGS)
                MOVE    _DIRBR_ENTRY, R7
                ADD     FAT32$DE_NAME, R7
                MOVE    R7, R8
                SYSCALL(strlen, 1)              ; R9: length of the name
                MOVE    _DIRBR_ENTRY, R7
                ADD     FAT32$DE_ATTRIB, R7
                MOVE    @R7, R7
                AND     FAT32$FA_DIR, R7        ; is it a directory?
                RBRA    _DIRBR_NEWELM2, Z       ; no
                ADD     _DIRBR_DSDESIZE, R9     ; add size of "<" ">"
                MOVE    DIRBR$FLAG_DIR, R6      ; R6: directory flag

                ; two characters per word plus the zero byte at the end:
                ; length / 2 + 1 words
_DIRBR_NEWELM2  AND     0xFFFB, SR              ; clear C: SHR shifts it in
                SHR     1, R9
                ADD     1, R9
                ADD     DIRBR$NAME, R9          ; R9: size of the data blob

                ; check if we still have enough heap to accommodate R9
                MOVE    R5, R7                  ; current heap memory
                ADD     R9, R7                  ; memory needed by new entry
                MOVE    R7, R10                 ; return new heap memory
                ADD     SLL$OVRHD_SIZE, R10
                CMP     R10, R4                 ; current+new+header <= max?
                RBRA    _DIRBR_NEOOM, N         ; no: out-of-memory!

                ; nothing is written to the heap before the check above, so
                ; an entry that does not fit leaves the memory behind the
                ; heap untouched
                MOVE    0, @R0                  ; init NEXT with 0
                MOVE    0, @R1                  ; init PREV with 0
                MOVE    R9, @R2                 ; put data size in SLL struct.
                MOVE    _DIRBR_ENTRY, R7        ; start cluster
                ADD     FAT32$DE_CLUS_LO, R7    ; (DE_CLUS_HI follows)
                MOVE    R3, R8
                ADD     DIRBR$CLUS_LO, R8
                MOVE    @R7++, @R8++            ; DIRBR$CLUS_HI follows
                MOVE    @R7, @R8
                MOVE    R10, R5                 ; R5: new current heap memory
                MOVE    _DIRBR_ENTRY, R8        ; pack the name
                ADD     FAT32$DE_NAME, R8
                MOVE    R3, R9
                ADD     DIRBR$NAME, R9
                MOVE    R6, R10                 ; R10: add "<" and ">"?
                RSUB    _DIRBR_PACK, 1          ; R8: behind the name
                OR      R9, R6                  ; R9: DIRBR$FLAG_NUM or 0
                MOVE    R3, R7
                ADD     DIRBR$FLAGS, R7
                MOVE    R6, @R7                 ; flags of the element

                MOVE    R5, R10                 ; R10: new current heap memory
                MOVE    R11, R9                 ; R9: pointer to new element
                XOR     R11, R11                ; R11: no error
                RBRA    _DIRBR_NERET, 1         ; return

                ; out of memory
_DIRBR_NEOOM    MOVE    R11, R8                 ; heap head did not change
                XOR     R9, R9                  ; no new element
                MOVE    R5, R10                 ; heap usage did not change
                MOVE    1, R11

                ; return
_DIRBR_NERET    DECRB
                RET

; Pack a name with two characters per word (the first one in the high byte)
; and end it with a zero byte, see DIRBR$NAME
; Input:
;   R8: name (zero-terminated, one character per word)
;   R9: target
;  R10: 0 = name of a file, not 0 = name of a directory: enclose it in "<"
;       and ">"
; Output:
;   R8: first word behind the packed name
;   R9: DIRBR$FLAG_NUM if the name consists of digits only, otherwise 0
;  R10: unchanged
_DIRBR_PACK     INCRB
                MOVE    R8, R0                  ; R0: name
                MOVE    R9, R1                  ; R1: target
                MOVE    R10, R2                 ; R2: "<" still to come?
                MOVE    R10, R3                 ; R3: ">" still to come?
                MOVE    DIRBR$FLAG_NUM, R7      ; R7: digits only so far
_DIRBR_PK_LOOP  RSUB    _DIRBR_PK_CHR, 1        ; R4: next character
                SWAP    R4, R5                  ; R5: it in the high byte
                RBRA    _DIRBR_PK_END, Z        ; end of the name: 0x0000
                RSUB    _DIRBR_PK_CHR, 1        ; R4: next character
                OR      R4, R5
                MOVE    R5, @R1++
                CMP     0, R4                   ; end of the name?
                RBRA    _DIRBR_PK_LOOP, !Z      ; no: next two characters
                RBRA    _DIRBR_PK_RET, 1
_DIRBR_PK_END   MOVE    R5, @R1++
_DIRBR_PK_RET   MOVE    R1, R8
                MOVE    R7, R9
                DECRB
                RET

; Next character for _DIRBR_PACK in R4, 0 at the end of the name. Works on
; the registers of _DIRBR_PACK, therefore no INCRB.
_DIRBR_PK_CHR   CMP     0, R2                   ; "<" first?
                RBRA    _DIRBR_PKC_NAME, Z      ; no
                XOR     R2, R2
                MOVE    _DIRBR_DS, R4
                RET
_DIRBR_PKC_NAME MOVE    @R0, R4                 ; next character of the name
                RBRA    _DIRBR_PKC_END, Z
                ADD     1, R0
                CMP     '0', R4                 ; below "0"?
                RBRA    _DIRBR_PKC_NAN, N
                CMP     R4, '9'                 ; above "9"?
                RBRA    _DIRBR_PKC_NAN, N
                RET
_DIRBR_PKC_NAN  XOR     R7, R7                  ; not a number
                RET
_DIRBR_PKC_END  CMP     0, R3                   ; ">" at the end?
                RBRA    _DIRBR_PKC_RET, Z       ; no: R4 = 0
                XOR     R3, R3
                MOVE    _DIRBR_DE, R4
_DIRBR_PKC_RET  RET

; SLL$SORT compare function that returns negative if (S0 < S1),
; zero if (S0 == S1), positive if (S0 > S1). These semantic are
; basically compatible with STR$CMP, but instead of expecting pointers
; to two strings, this compare function is expecting two pointers to
; SLL records, while the pointer to the first one is given in R8 and
; treated as "S0" and the second one in R9 and treated as "S1".
;
; The order: case-insensitive (a..z equal A..Z), in a directory name the
; "<" and ">" count as the characters 1 and 2 (directories come first and a
; shorter directory name before a longer one that starts the same way), and
; if both names consist of digits only, then the shorter name is the smaller
; one, so that 1, 2, ..., 10, 11, ... are sorted by their value. The names
; are compared directly in their packed form (two characters per word, see
; DIRBR$NAME), without copying them.
;
; MUST preserve R8, R9 and R11 across the call. SLL$SORT keeps the
; comparator pointer in the unbanked R11 across every merge iteration, so
; writing to R11 silently breaks the sort after the first iteration. This
; function only uses R0 to R7 of its own register bank and R10.

_DIRBR_COMPARE  INCRB

                MOVE    R8, R0
                ADD     SLL$DATA, R0
                MOVE    R0, R6
                ADD     DIRBR$FLAGS, R6
                MOVE    @R6, R6                 ; R6: flags of S0
                ADD     DIRBR$NAME, R0          ; R0: name of S0
                MOVE    R9, R1
                ADD     SLL$DATA, R1
                MOVE    R1, R7
                ADD     DIRBR$FLAGS, R7
                MOVE    @R7, R7                 ; R7: flags of S1
                ADD     DIRBR$NAME, R1          ; R1: name of S1

                ; both names consist of digits only: the shorter one is the
                ; smaller one
                AND     R7, R6
                AND     DIRBR$FLAG_NUM, R6
                RBRA    _DIRBR_CMP_CHR, Z
                MOVE    R0, R2
                RSUB    _DIRBR_PLEN, 1
                MOVE    R3, R4                  ; R4: length of S0
                MOVE    R1, R2
                RSUB    _DIRBR_PLEN, 1          ; R3: length of S1
                SUB     R3, R4
                RBRA    _DIRBR_CMP_CHR, Z       ; same length: compare chars.
                MOVE    R4, R10
                RBRA    _DIRBR_CMP_RET, 1

                ; R6/R7: does S0/S1 start with "<" (directory name)?
_DIRBR_CMP_CHR  XOR     R6, R6
                MOVE    @R0, R2
                SWAP    R2, R2
                AND     0x00FF, R2
                CMP     _DIRBR_DS, R2
                RBRA    _DIRBR_CMP_D1, !Z
                MOVE    1, R6
_DIRBR_CMP_D1   XOR     R7, R7
                MOVE    @R1, R2
                SWAP    R2, R2
                AND     0x00FF, R2
                CMP     _DIRBR_DS, R2
                RBRA    _DIRBR_CMP_LP, !Z
                MOVE    1, R7

                ; equal words: two equal characters, go on until the end
_DIRBR_CMP_LP   MOVE    @R0++, R2               ; R2: two characters of S0
                MOVE    @R1++, R3               ; R3: two characters of S1
                CMP     R2, R3
                RBRA    _DIRBR_CMP_DIF, !Z
                CMP     0x0100, R2              ; first character 0?
                RBRA    _DIRBR_CMP_EQ, N        ; yes: both names end
                MOVE    R2, R4
                AND     0x00FF, R4              ; second character 0?
                RBRA    _DIRBR_CMP_EQ, Z        ; yes: both names end
                RBRA    _DIRBR_CMP_LP, 1

                ; the words differ: compare their characters one by one
_DIRBR_CMP_DIF  SWAP    R2, R4
                AND     0x00FF, R4
                MOVE    R6, R5
                RSUB    _DIRBR_CMAP, 1
                MOVE    R4, R10                 ; R10: 1st character of S0
                SWAP    R3, R4
                AND     0x00FF, R4
                MOVE    R7, R5
                RSUB    _DIRBR_CMAP, 1          ; R4: 1st character of S1
                SUB     R4, R10
                RBRA    _DIRBR_CMP_RET, !Z      ; they differ: done
                CMP     0, R4                   ; both names end?
                RBRA    _DIRBR_CMP_RET, Z       ; yes: R10 = 0
                MOVE    R2, R4
                AND     0x00FF, R4
                MOVE    R6, R5
                RSUB    _DIRBR_CMAP, 1
                MOVE    R4, R10                 ; R10: 2nd character of S0
                MOVE    R3, R4
                AND     0x00FF, R4
                MOVE    R7, R5
                RSUB    _DIRBR_CMAP, 1          ; R4: 2nd character of S1
                SUB     R4, R10
                RBRA    _DIRBR_CMP_RET, !Z      ; they differ: done
                CMP     0, R4                   ; both names end?
                RBRA    _DIRBR_CMP_LP, !Z       ; no: next two characters
_DIRBR_CMP_EQ   XOR     R10, R10

_DIRBR_CMP_RET  DECRB
                RET

; Character R4 as _DIRBR_COMPARE sees it: a..z become A..Z and, if R5 is not
; 0 (directory name), "<" becomes 1 and ">" becomes 2. Works on the registers
; of _DIRBR_COMPARE, therefore no INCRB.
_DIRBR_CMAP     CMP     'a', R4                 ; below "a"?
                RBRA    _DIRBR_CMAP_D, N
                CMP     R4, 'z'                 ; above "z"?
                RBRA    _DIRBR_CMAP_D, N
                SUB     0x0020, R4              ; upper case
                RET
_DIRBR_CMAP_D   CMP     0, R5                   ; directory name?
                RBRA    _DIRBR_CMAP_R, Z
                CMP     _DIRBR_DS, R4
                RBRA    _DIRBR_CMAP_1, !Z
                MOVE    1, R4
                RET
_DIRBR_CMAP_1   CMP     _DIRBR_DE, R4
                RBRA    _DIRBR_CMAP_R, !Z
                MOVE    2, R4
_DIRBR_CMAP_R   RET

; Length of the packed name at R2 in R3 (uses R5). Works on the registers of
; _DIRBR_COMPARE, therefore no INCRB.
_DIRBR_PLEN     XOR     R3, R3
_DIRBR_PLEN_L   MOVE    @R2++, R5
                CMP     0x0100, R5              ; first character 0?
                RBRA    _DIRBR_PLEN_R, N        ; yes: end of the name
                ADD     1, R3
                AND     0x00FF, R5              ; second character 0?
                RBRA    _DIRBR_PLEN_R, Z        ; yes: end of the name
                ADD     1, R3
                RBRA    _DIRBR_PLEN_L, 1
_DIRBR_PLEN_R   RET

; Runs the filter function given to DIRBROWSE_READ on the directory entry in
; _DIRBR_ENTRY before the entry takes any heap space, so that hidden entries
; do not count against the heap. The filter function gets the same string as
; it got when it ran on the heap copy: the name in upper case and, for a
; directory, enclosed in "<" and ">".
; Output: R8 = 0: show the entry, 1: hide it; R9, R10 and R11 are preserved
_DIRBR_FILTENT  INCRB

                MOVE    R9, R0                  ; backup R9, R10 & R11
                MOVE    R10, R1
                MOVE    R11, R2

                MOVE    _DIRBR_ENTRY, R4        ; R6: directory flag
                ADD     FAT32$DE_ATTRIB, R4
                MOVE    @R4, R6
                AND     FAT32$FA_DIR, R6        ; directory?
                RBRA    _DIRBR_FE_1, Z          ; no: R6 = 0
                MOVE    1, R6                   ; yes: R6 = 1

                ; copy the name to the stack (with "<" and ">" if it is a
                ; directory) and make it upper case
_DIRBR_FE_1     MOVE    _DIRBR_ENTRY, R4
                ADD     FAT32$DE_NAME, R4       ; R4: name
                MOVE    R4, R8
                SYSCALL(strlen, 1)
                MOVE    R9, R5                  ; R5: length of the name
                MOVE    R9, R3
                ADD     1, R3                   ; zero terminator
                ADD     R6, R3                  ; "<" and ">" if directory
                ADD     R6, R3                  ; R3: stack space needed
                SUB     R3, SP
                MOVE    SP, R7                  ; R7: copy on the stack
                MOVE    R7, R9
                CMP     0, R6                   ; directory?
                RBRA    _DIRBR_FE_2, Z
                MOVE    _DIRBR_DS, @R9++        ; yes: "<" before the name
_DIRBR_FE_2     MOVE    R4, R8
                SYSCALL(strcpy, 1)
                CMP     0, R6                   ; directory?
                RBRA    _DIRBR_FE_3, Z
                ADD     R5, R9                  ; yes: ">" after the name
                MOVE    _DIRBR_DE, @R9++
                MOVE    0, @R9
_DIRBR_FE_3     MOVE    R7, R8
                SYSCALL(str2upper, 1)           ; R8 contains upper string

                ; call filter function (callback function)
                ; R8: filename in upper-case
                ; R9: 0=file/1=directory
                ; R10: SF_CONTEXT
                ; R11: SF_CONTEXT_DATA
                MOVE    R6, R9
                MOVE    SF_CONTEXT, R10
                MOVE    @R10, R10
                MOVE    SF_CONTEXT_DATA, R11
                MOVE    @R11, R11
                MOVE    _DIRBR_FILTERFN, R4
                ASUB    @R4, 1

                ADD     R3, SP                  ; restore stack
                MOVE    R0, R9                  ; restore R9, R10 & R11
                MOVE    R1, R10
                MOVE    R2, R11
                DECRB
                RET
